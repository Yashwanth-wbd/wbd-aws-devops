# iam-oidc

Lets GitHub Actions log in to this AWS account **without stored keys**, and creates the
pipeline roles. Background: [docs/03-github-oidc.md](../../../docs/03-github-oidc.md).

**Status:** implemented in Step 3.

## What it creates

| Resource | Name (dev) | Trusted GitHub OIDC subjects | Permissions |
|---|---|---|---|
| OIDC provider | `token.actions.githubusercontent.com` | – | – |
| Role | `mmm-dev-gha-plan` | `environment:dev`, `pull_request` (off in prod), `ref:refs/heads/main` (nightly drift check) | `ReadOnlyAccess` + write the state lock file + state KMS + read `mmm/<env>/*` secret values (needed to refresh generated secrets) |
| Role | `mmm-dev-gha-apply` | `environment:dev` | `AdministratorAccess`, capped by the permission boundary |
| Role | `mmm-dev-gha-deploy` | `environment:dev` | Register task definitions, update `mmm-dev-*` services, run the `mmm-dev-migrate` task, pass `mmm-dev-task-*` / `mmm-dev-ecs-task-exec` roles to ECS, read migration logs, prod pre-migration Aurora cluster snapshot (`cluster:<prefix>-aurora`), read / write the SageMaker image pointers `/mmm/<env_short>/images/*`, and publish versions / move the `live` alias of `deploy_lambda_functions` (results publisher). With `deploy_dry_run` (dev, staging): start / describe `dryrun-*` executions of `<prefix>-optimization`, write `runs/dryrun-*` in the results bucket, list `curves/` in the models bucket |
| Role | `mmm-dev-gha-ecr-push` | `environment:dev`, `ref:refs/heads/main` (dev only) | Push/pull `mmm/*` repositories in this account |
| Role | `mmm-dev-gha-ecr-read` | the next environment (dev → `staging`, staging → `prod`) | Pull `mmm/*` to copy images forward |
| Role (`enable_model_governance`) | `mmm-dev-gha-model-eval` | `ref:refs/heads/main` (hourly evaluation) | Read the Model Registry groups `<prefix>-*` and the evaluation reports; set a model package to **Rejected** only; tag it |
| Role (`enable_model_governance`) | `mmm-dev-gha-model-approve` | `environment:dev-model-promotion` (WBD model approver) | Same, plus set **Approved** and publish the approved response curves to `models/curves/*` |

Subjects are always `repo:<github_org>/<github_repo>:...`, so no other repository can use
these roles. Every role has the permission boundary and a 1-hour session limit.

### Why gha-apply has AdministratorAccess

Terraform creates almost every kind of AWS resource, so a narrow list breaks every time a
module is added. Instead it is limited by:

1. the **permission boundary** (no IAM users or keys, no roles without the boundary, no
   disabling security services, approved regions only);
2. the **trust policy**: only jobs in the approved GitHub Environment can assume it, and prod
   requires a WBD approver;
3. **CloudTrail**, which records every call with the GitHub run in the session name.

### First apply (chicken-and-egg)

The roles do not exist until this module is applied once, so the first apply of the dev
stack is run by a DevOps engineer with the SSO `DevOps` profile. Until the CI/CD pipeline
exists (Step 11), dev applies keep running that way; after Step 11 they run only from
GitHub Actions (`terraform.yml`).

The v2 architecture changed the deploy policy (Aurora snapshot, SSM image pointers, Lambda release
instead of the frontend / CloudFront / MWAA statements) and added the model governance roles. Apply
this once with the SSO `DevOps` profile before the first pipeline run.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | – | e.g. `mmm-dev` |
| `environment` | string | – | GitHub Environment: `dev`, `staging`, `prod` |
| `env_short` | string | – | `dev`, `stg`, `prd` |
| `github_org`, `github_repo` | string | – | Repository allowed to assume the roles |
| `create_oidc_provider` | bool | `true` | `false` + `existing_oidc_provider_arn` if the account already has one |
| `permissions_boundary_arn` | string | – | From the permission-boundary module |
| `plan_allow_pull_requests` | bool | `true` | Set `false` in prod |
| `plan_allow_main_branch` | bool | `true` | Workflows on `main` without an Environment (drift check) may plan. The role is read-only, and `main` only holds reviewed code |
| `ecr_push_allow_main_branch` | bool | `false` | `true` in dev (CI build on main) |
| `ecr_read_trusted_environments` | list(string) | `[]` | dev `["staging"]`, staging `["prod"]` |
| `state_bucket_name`, `state_kms_key_arn` | string | – | From `infra/bootstrap` |
| `secrets_kms_key_arn`, `s3_kms_key_arn`, `ecr_kms_key_arn` | string | – | From the kms module |
| `deploy_lambda_functions` | list(string) | `["results-publisher"]` | Function names (without prefix) the deploy role may release |
| `deploy_dry_run` | object({ results_bucket_arn, models_bucket_arn }) | `null` | Post-release optimization dry run by the deploy role (the stacks set it in dev and staging) |
| `enable_model_governance` | bool | `false` | Create `gha-model-eval` / `gha-model-approve` (= `enable_data_platform`) |
| `max_session_duration` | number | `3600` | Seconds |

## Outputs

| Name | Description |
|---|---|
| `oidc_provider_arn` | Provider ARN |
| `role_arns` | `{ plan, apply, deploy, ecr_push, ecr_read }` (+ `model_eval`, `model_approve`), used as GitHub variables |
| `trusted_subjects` | Subjects each role trusts, for review |

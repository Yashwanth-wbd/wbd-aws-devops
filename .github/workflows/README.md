# .github/workflows

GitHub Actions pipelines. The full guide (flow, GitHub setup, app contract, rollback) is
[docs/09-cicd-pipelines.md](../../docs/09-cicd-pipelines.md).

**Status:** v3 architecture (ALB with Okta OIDC sign-in, ECS api / ui, RDS PostgreSQL, SQS run
queue, SageMaker optimization and training, Step Functions incl. drift monitor, Lambda publisher).
Data and model governance: [docs/10](../../docs/10-data-platform-and-model-governance.md).

| File | Trigger | Environment(s) | AWS roles |
|---|---|---|---|
| `api-ci.yml` | `apps/api/**` PR / main | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `ui-ci.yml` | `apps/ui/**` PR / main (npm lint / test / build, image `mmm/ui`) | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `optimizer-ci.yml` | `apps/sagemaker-optimizer/**` PR / main | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `training-ci.yml` | `apps/sagemaker-training/**` PR / main | `dev` (push job only) | `mmm-dev-gha-ecr-push` |
| `publisher-ci.yml` | `apps/results-publisher/**` PR / main (tests only, no image) | none | none |
| `_python-service-ci.yml` | called by the four above (`build_image: false` for the Lambda) | | |
| `deploy.yml` | CI finished on main → dev; `vX.Y.Z-rcN` → staging; `vX.Y.Z` → prod; manual. Components: `api`, `ui` (ECS), `optimizer`, `training` (SSM image pointers), `publisher` (Lambda version + alias `live`) | the target | previous env `gha-ecr-read`, own `gha-ecr-push`, own `gha-deploy` |
| `terraform.yml` | `infra/**`, `data/model-thresholds.yaml` PR / main; nightly; manual | `dev` → `staging` → `prod` (apply) | `gha-plan` (PR, drift), `gha-apply` |
| `_terraform-apply.yml` | called by `terraform.yml` | the target | `gha-apply` |
| `repo-checks.yml` | every PR / main | none | none |
| `databricks.yml` | `data/databricks/**` main → dev; manual → staging / prod | the target | none: Databricks GitHub OIDC federation (deploy service principal) |
| `model-governance.yml` | hourly; manual evaluate / promote / rollback (promote publishes curves + drift baseline and writes `approval.json`) | none (evaluate); `<env>-model-promotion` (promote, rollback) | `gha-model-eval` (reject only), `gha-model-approve` |

Rules for changes here:

- Every job that touches AWS declares `permissions: id-token: write` and gets its role ARN from
  `vars.*`. Never add AWS keys as secrets.
- Jobs that change an environment must declare `environment:`. That is what applies the approval
  rules and makes the OIDC `sub` match the role's trust policy.
- Values from events (branch names, inputs) go through `env:` into scripts, never straight into
  `run:` with `${{ }}`, which prevents script injection.
- A component whose `apps/<folder>` does not exist yet is skipped, so the pipelines work before the
  app teams add their code.
- `repo-checks.yml` runs actionlint on this folder.

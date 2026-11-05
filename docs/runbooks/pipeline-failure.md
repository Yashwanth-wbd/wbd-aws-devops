# Runbook: pipeline failure

First stop: the failed step's log and the run summary. The common errors and fixes are in
[docs/09 §7](../09-cicd-pipelines.md#7-troubleshooting); this page is the order to work through.

## By workflow

| Workflow | Failed step | What to do |
|---|---|---|
| `api-ci` / `ui-ci` / `optimizer-ci` / `training-ci` | lint, type-check, tests, coverage | App team fixes in a PR. Never lower coverage gates to get green |
| | Trivy dependency / image scan | Upgrade the package or base image (fixable Critical/High). False positive: `.trivyignore` with reason and expiry, security approval |
| | push (`AssumeRoleWithWebIdentity`) | `ECR_PUSH_ROLE_ARN` in the `dev` environment; job must run on `main` |
| `publisher-ci` | tests only | Fix `apps/results-publisher` in a PR |
| `deploy` | resolve | Tag format `vX.Y.Z-rcN` / `vX.Y.Z`; prod dispatch must run on a release tag |
| | Find source images | App changed after the last good dev build, or prod tag not on the rc commit |
| | Copy images | `SOURCE_ECR_READ_ROLE_ARN` / `SOURCE_ECR_REGISTRY`; upstream `gha-ecr-read` trusts this environment |
| | Aurora snapshot (prod) | Fix IAM or cluster state; snapshot id `mmm-<env>-predeploy-...` |
| | Database migration | Nothing deployed yet. Read migration log; fix forward with a new rc. Prod: pre-deploy snapshot exists |
| | Deploy services / circuit breaker | Automatic rollback already ran. [ecs-task-stuck.md](ecs-task-stuck.md) |
| | SageMaker pointers / publisher | Rollback step restores SSM and Lambda alias; fix image or publisher code |
| | Smoke test | Rolled back automatically. Check WAF (403), Cognito redirect on `/`, `/api/health` 200 |
| | Roll back (itself failed) | SEV1 in prod: manual rollback [rollback.md](rollback.md) now |
| `terraform` | fmt / validate / tflint / Checkov | Fix in the PR |
| | mock plan | `.\scripts\mock-plan.ps1 -Environment <env> -ShowPlan` locally |
| | plan / apply | Never apply by hand to "unstick"; fix code. State lock: see below |
| | nightly drift | CloudTrail for out-of-band changes; import or revert via PR |
| `repo-checks` | secret scan | [security-incident.md](security-incident.md) – rotate first |
| | environment sync | Edit `dev` / `ecs/dev`, run `.\scripts\sync-environments.ps1`, commit |
| `databricks.yml` | bundle deploy | Data team; needs `DATABRICKS_HOST`, `DATABRICKS_CLIENT_ID`, connection secret |
| `model-governance.yml` | evaluate / promote / rollback | [docs/10 §9](../10-data-platform-and-model-governance.md#9-troubleshooting) |

## Terraform state lock

A cancelled apply can leave a lock (S3 native lock file `<key>.tflock` in the state bucket).
Make sure no apply is running (Actions tab), then remove it with the DevOps profile:

```bash
terraform -chdir=infra/environments/<env> init
terraform -chdir=infra/environments/<env> force-unlock <LOCK_ID from the error>
```

Record it in the ticket; re-run the workflow.

## GitHub or AWS outage

GitHub down: no deploys. Urgent prod fix → [break-glass.md](break-glass.md). AWS region issue →
check AWS Health before debugging the pipeline.

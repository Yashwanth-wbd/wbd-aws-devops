# Runbook: pipeline failure

First stop: the failed step's log and the run summary. The common errors and fixes are in
[docs/09 §7](../09-cicd-pipelines.md#7-troubleshooting); this page is the order to work through.

## By workflow

| Workflow | Failed step | What to do |
|---|---|---|
| `api-ci` / `optimizer-ci` / `genai-ci` | lint, type-check, tests, coverage | App team fixes in a PR. Never lower `coverage_min` or skip steps to get green |
| | Trivy dependency / image scan | Upgrade the package or base image (fixable Critical/High). A false positive: `.trivyignore` entry with reason and expiry date, approved by security |
| | push (`AssumeRoleWithWebIdentity`) | `ECR_PUSH_ROLE_ARN` variable in the `dev` environment; job must run on `main` |
| `deploy` | resolve | Tag format must be `vX.Y.Z-rcN` / `vX.Y.Z`; prod dispatch must run on a release tag |
| | Find source images (`find-build` / `find-rc`) | The app changed after the last good dev build (fix CI on `main`, re-tag `-rc2`), or the prod tag is not on the rc commit |
| | Copy images | `SOURCE_ECR_READ_ROLE_ARN` / `SOURCE_ECR_REGISTRY` variables; the previous environment's `gha-ecr-read` trusts this environment |
| | Database migration | Nothing deployed yet. Read the migration log in the job; fix forward with a new rc. Prod: the pre-deploy snapshot exists |
| | Deploy services / circuit breaker | Automatic rollback already ran. [ecs-task-stuck.md](ecs-task-stuck.md) for the cause |
| | Smoke test | Rolled back automatically. Check WAF (403), CloudFront, `/health` |
| | Roll back (itself failed) | SEV1 in prod: do the manual rollback in [rollback.md](rollback.md) now |
| `terraform` | fmt / validate / tflint / Checkov | Fix in the PR (Checkov skips need a `#checkov:skip=<id>:<reason>` reviewed by security) |
| | mock plan | `.\scripts\mock-plan.ps1 -Environment <env> -ShowPlan` reproduces it locally |
| | plan / apply | Read the error: quota, name already exists, permission boundary deny, provider bug. Never apply by hand to "unstick" it; fix the code. State lock left behind: see below |
| | nightly drift | Someone changed AWS outside Terraform: find it in CloudTrail; import it into code or let the next apply revert it (decide with the owner) |
| `repo-checks` | secret scan | **Treat as a leaked secret:** [security-incident.md](security-incident.md) (rotate first, then remove from history) |
| | environment sync | Edit `infra/environments/dev` / `ecs/dev`, run `.\scripts\sync-environments.ps1`, commit |
| `data` / `model-governance` | | [docs/10 §9](../10-data-platform-and-model-governance.md#9-troubleshooting) |

## Terraform state lock

A cancelled apply can leave a lock (S3 native lock file `<key>.tflock` in the state bucket).
Make sure no apply is running (Actions tab), then remove it with the DevOps profile:

```bash
terraform -chdir=infra/environments/<env> init      # with the backend config
terraform -chdir=infra/environments/<env> force-unlock <LOCK_ID from the error>
```

Record it in the ticket; re-run the workflow.

## GitHub or AWS outage

GitHub down: no deploys. Urgent prod fix → [break-glass.md](break-glass.md). AWS region issue →
check AWS Health (`aws health describe-events` from us-east-1) before debugging the pipeline.

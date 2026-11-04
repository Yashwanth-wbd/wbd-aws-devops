# Runbook: roll back

Decide **what** is bad first: app image, frontend, database schema/data, infrastructure, data
pipeline (DAGs), model, or GenAI. Practise each in staging (Release 1 gate R9).

| What | Fastest safe rollback | Time |
|---|---|---|
| App (api / workers / genai-gateway) | Redeploy the previous version with `deploy.yml` dispatch, migrations off | 5–10 min |
| App, pipeline unavailable | `aws ecs update-service --task-definition <previous revision>` ([break-glass.md](break-glass.md) in prod) | 3–5 min |
| Frontend | `deploy-frontend.sh switch` to the previous release folder | 1 min |
| Infrastructure | Revert the PR, merge, approve the apply | 15–30 min |
| Database data | Point-in-time restore ([db-restore.md](db-restore.md)) | 30–60 min |
| DAGs | Re-tag the previous `data-vX.Y.Z` ([docs/10 §6](../10-data-platform-and-model-governance.md#6-releasing-dags-datayml)) | 10 min |
| Model | Move the `production` alias back ([model-rollback.md](model-rollback.md)) | 5 min + approval |
| GenAI | Flag off ([genai.md](genai.md)) | 5 min |

## App

```bash
# previous good version from the last release record, or:
aws ecs describe-services --cluster $P-ecs --services $P-api --query 'services[0].deployments[].taskDefinition'

# prod: run on the previous release tag (the workflow refuses other refs for prod)
gh workflow run deploy.yml --ref v1.3.2 -f environment=prod -f run_migrations=false -f components=all
# staging / dev: any ref, give the tag that is already in that ECR
gh workflow run deploy.yml --ref main -f environment=staging -f image_tag=v1.3.2-rc1 -f run_migrations=false
```

Without the pipeline (prod needs `BreakGlass` or `mmm-prd-devops`):

```bash
aws ecs list-task-definitions --family-prefix $P-api --sort DESC --max-items 5
aws ecs update-service --cluster $P-ecs --service $P-api --task-definition $P-api:<previous revision>
aws ecs wait services-stable --cluster $P-ecs --services $P-api
```

Repeat for `whatif-worker` / `optimizer-worker` / `genai-gateway` if they changed. Afterwards
redeploy the same version through the pipeline so the release record is complete.

**Schema:** migrations are expand-then-contract, so the previous app version works on the new
schema. If a migration itself destroyed data, restore ([db-restore.md](db-restore.md)); the
prod deploy made snapshot `mmm-prd-predeploy-<version>-<run>` right before it.

## Frontend

```bash
bash scripts/deploy-frontend.sh switch <FRONTEND_KVS_ARN> v1.3.2   # GitHub variable FRONTEND_KVS_ARN
```

## Infrastructure

`git revert <merge commit>` → PR → plan shows the reverse change → merge → approvals. For a
resource Terraform cannot recreate quickly (RDS, buckets) read the plan carefully: never accept a
replace of `$P-pg` or a data bucket – stop and escalate.

## Verify

Dashboard back to normal for 15 minutes, `aws cloudwatch describe-alarms --state-value ALARM
--alarm-name-prefix $P` empty, smoke test (`scripts/smoke.sh <APP_URL>`) passes.

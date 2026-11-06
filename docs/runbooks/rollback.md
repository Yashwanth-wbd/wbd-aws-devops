# Runbook: roll back

Decide **what** is bad first: app image (`api` / `ui`), SageMaker optimizer/training image pointers,
results publisher Lambda, database schema/data, infrastructure, model refresh pipeline, model
governance, or GenAI. Practise each in staging (Release 1 gate R9).

| What | Fastest safe rollback | Time |
|---|---|---|
| App (`api`, `ui`) | Redeploy the previous version with `deploy.yml` dispatch, migrations off | 5–10 min |
| App, pipeline unavailable | `aws ecs update-service --task-definition <previous revision>` ([break-glass.md](break-glass.md) in prod) | 3–5 min |
| SageMaker optimizer / training image | `deploy.yml` dispatch with previous tag, or restore previous SSM values | 2–5 min |
| Results publisher | `scripts/lambda-release.sh switch mmm-<env>-results-publisher <version>` (version from release record) | 1–2 min |
| Infrastructure | Revert the PR, merge, approve the apply | 15–30 min |
| Database data | RDS point-in-time restore ([db-restore.md](db-restore.md)) | 30–60 min |
| Model curves (governance) | `model-governance.yml` `rollback` action ([model-rollback.md](model-rollback.md)) | 5 min + approval |
| GenAI | Flag off ([genai.md](genai.md)) | 5 min |

## App (ECS)

```bash
# previous good version from the last release record, or:
aws ecs describe-services --cluster $P-ecs --services $P-api $P-ui --query 'services[].deployments[].taskDefinition'

# prod: run on the previous release tag (the workflow refuses other refs for prod)
gh workflow run deploy.yml --ref v1.3.2 -f environment=prod -f run_migrations=false -f components=all
# staging / dev: any ref, give the tag that is already in that ECR
gh workflow run deploy.yml --ref main -f environment=staging -f image_tag=v1.3.2-rc1 -f run_migrations=false
```

Without the pipeline (prod needs `BreakGlass` or `mmm-prd-devops`):

```bash
aws ecs list-task-definitions --family-prefix $P-api --sort DESC --max-items 5
aws ecs update-service --cluster $P-ecs --service $P-api --task-definition $P-api:<previous revision>
aws ecs update-service --cluster $P-ecs --service $P-ui --task-definition $P-ui:<previous revision>
aws ecs wait services-stable --cluster $P-ecs --services $P-api $P-ui
```

Afterwards redeploy the same version through the pipeline so the release record is complete.

**Schema:** migrations are expand-then-contract, so the previous app version works on the new
schema. If a migration itself destroyed data, restore ([db-restore.md](db-restore.md)); the prod
deploy made cluster snapshot `mmm-prd-predeploy-<version>-<run>` right before it.

## SageMaker images (SSM)

The release record lists previous SSM values for `/mmm/<env_short>/images/sagemaker-optimizer` and
`sagemaker-training`. Either dispatch `deploy.yml` with the previous image tag, or (emergency):

```bash
aws ssm put-parameter --name /mmm/$E/images/sagemaker-optimizer --value '<previous digest URI>' --overwrite
```

New optimization runs pick up the pointer immediately; in-flight Step Functions executions keep
the image they resolved at start.

## Results publisher (Lambda)

```bash
# version from the release record, or:
scripts/lambda-release.sh current mmm-$E-results-publisher   # shows live alias target
scripts/lambda-release.sh switch mmm-$E-results-publisher <previous-version>
```

## Infrastructure

`git revert <merge commit>` → PR → plan shows the reverse change → merge → approvals. For the RDS
instance, the run queue or buckets, read the plan carefully: never accept an unintended replace of
the DB instance or the queues – stop and escalate.

## Verify

Dashboard back to normal for 15 minutes, `aws cloudwatch describe-alarms --state-value ALARM
--alarm-name-prefix $P` empty, smoke test (`scripts/smoke.sh <APP_URL>`) passes.

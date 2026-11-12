# Runbook: Glue job failed

The model-refresh and model-monitor state machines run the Glue jobs
`mmm-<env_short>-glue-{bronze,silver,gold,export-training,export-rds,export-monitor}` with
`startJobRun.sync`. A failed run fails the execution (`mmm-<env>-model-refresh-failed` /
`-model-monitor-failed`) and the EventBridge rules add an email with the job name:
`glue-job-failed` (`FAILED`, `TIMEOUT`, `ERROR`) and `glue-data-quality-failed` (Silver ruleset).

Planners are not affected: no new model is trained, the last approved model stays in use. A
failed export-rds means the RDS reference tables keep the previous refresh's data.

## 1. Find the job run

```bash
# job run id and state are in the failed state's output / error
aws stepfunctions get-execution-history --execution-arn <arn> --reverse-order --max-results 30 \
  --query 'events[?type==`TaskFailed`].taskFailedEventDetails'
aws glue get-job-runs --job-name mmm-<env_short>-glue-<job> --max-results 5 \
  --query 'JobRuns[].[Id,JobRunState,ErrorMessage,ExecutionTime,Arguments."--business_unit"]' --output table
aws logs tail /aws-glue/jobs/mmm-<env_short> --since 6h --filter-pattern '"<job run id>"'
```

Console: Glue → ETL jobs → the job → Runs (Spark UI, metrics). Data Quality: Glue → Data Catalog →
the Silver table → Data quality, or `aws glue list-data-quality-results`.

## 2. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| `SystemExit: seed script` | `glue.yml` has not uploaded the real script yet | Data engineers add `data/glue/jobs/<job>.py`; run `glue.yml` for the environment |
| Python / Spark exception in the log | Job code | Data engineers, with the job run id |
| `glue-data-quality-failed`, Silver fails | A rule in `data/glue/dq/silver.dqdl` failed (bad or missing source data) | Data engineers check the source export; never relax a rule without the data owner |
| `TIMEOUT` | Data volume grew or a skewed join | Raise `glue_number_of_workers` / `glue_worker_type` or `glue_job_timeout_minutes` (PR) |
| `Exceeded maximum concurrent compute capacity` / `ConcurrentRunsExceededException` | Account DPU quota or several BUs at once | Service Quotas (Glue DPUs); stagger the refresh schedules |
| ENI / `Insufficient free addresses` | The connection subnet is out of IPs | Free IPs or move the connection to another private-app subnet |
| `AccessDenied` on S3 / KMS | Wrong path (outside the role's prefixes) or a new BU key | Check the job arguments; new BU = Terraform apply first |
| export-rds `password authentication failed` / `PAM` | `mmm_etl` missing or the `rds/etl` secret not on the proxy | Run the DB bootstrap with the data platform on ([db-bootstrap](../../scripts/README.md)); proxy secret list in `main.tf` |
| export-rds `permission denied for table` | The app migrations did not grant the reference tables to `mmm_etl` | App team adds the grant in a migration |

## 3. Re-run

Glue jobs are idempotent per `refresh_id` (they overwrite their own partition). After the fix:

```bash
scripts/trigger-model-refresh.sh <env> <business_unit>
```

This runs a new export too. To test only a job, start it with the arguments of the failed run
(`aws glue start-job-run --job-name ... --arguments file://args.json`) in dev.

## 4. After

Record the execution ARN, the job run id and the cause in the ticket.

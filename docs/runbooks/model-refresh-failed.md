# Runbook: model refresh failed

A model refresh is one Step Functions execution of `mmm-<env>-model-refresh` per business unit,
started by EventBridge Scheduler (`mmm-<env_short>-refresh-<bu>`) or an `mmm.refresh` event
(`scripts/trigger-model-refresh.sh`). It runs the Databricks export (raw Parquet to landing), the
Glue jobs Bronze → Silver (Data Quality) → Gold → export-training + export-rds (Parquet to
`lakehouse/rds-export/`), the results/data publisher (`reference_data` → RDS), SageMaker
training, evaluation, registration (`PendingManualApproval`), SageMaker ML Lineage and the
results/data publisher (`model_results` → RDS). Use this runbook when the
`mmm-<env>-model-refresh-failed` alarm fires or a scheduled refresh produced no new model package.

A failed refresh does **not** affect planners: the optimizer keeps using the last approved model
and its curves in `models/curves/<bu>/`.

## 1. Find the execution

```bash
aws stepfunctions list-executions --state-machine-arn "$MODEL_REFRESH_STATE_MACHINE_ARN" \
  --status-filter FAILED --max-results 10

aws stepfunctions describe-execution --execution-arn <arn> \
  --query '{status:status,input:input,error:error,cause:cause}'

aws stepfunctions get-execution-history --execution-arn <arn> --reverse-order --max-results 30 \
  --query 'events[?type==`TaskFailed` || type==`ExecutionFailed`].[timestamp,type,executionFailedEventDetails,taskFailedEventDetails]'
```

GitHub Environment variable `MODEL_REFRESH_STATE_MACHINE_ARN` (or `terraform output data_platform`)
gives the ARN. Logs: `/aws/states/mmm-<env>-model-refresh`.

## 2. Where to look by step

| Step (state machine) | Logs / resources |
|---|---|
| GetTrainingImage | SSM `/mmm/<env_short>/images/sagemaker-training` – must be `<registry>/<repo>@<digest>`, not `:unset` |
| StartExport / GetExportStatus / ExportFailed | Export Lambda `mmm-<env_short>-databricks-export` log; Databricks workspace → Jobs → run id (`$.export.run_id`) – [databricks-export-failed.md](databricks-export-failed.md) |
| Bronze / Silver / Gold | Glue job `mmm-<env_short>-glue-<job>` run, log group `/aws-glue/jobs/mmm-<env_short>`; Silver Data Quality result – [glue-job-failed.md](glue-job-failed.md) |
| GlueExports (ExportTraining, ExportReferenceData) | Same Glue logs; snapshot `s3://<training-data>/<bu>/<refresh_id>/`; reference data `s3://<lakehouse>/rds-export/<bu>/<refresh_id>/` (+ `_manifest.json`) |
| PublishReferenceData | Publisher log `/aws/lambda/mmm-<env_short>-results-publisher` (event `reference_data`): missing manifest, RDS table missing (app migration), `Task timed out` (raise `publisher_timeout_seconds`, max 900, or `publisher_memory_mb`). Nothing is trained yet – re-run the refresh after the fix |
| TrainModel | CloudWatch `/aws/sagemaker/TrainingJobs`; console → SageMaker → Training jobs |
| EvaluateModel | CloudWatch `/aws/sagemaker/ProcessingJobs`; report `s3://<models>/evaluation/<bu>/<refresh_id>/evaluation.json` |
| RegisterModel | Model package group `mmm-<env_short>-<bu>` must exist (created by Terraform per BU) |
| RecordLineage / RecordLineageArtifacts / LineageNotRecorded | Does not fail the execution; alarm `mmm-<env_short>-lineage-record-failed-<bu>`. `$.lineage_error` in the execution output (SageMaker throttling or `AccessDenied` on `context/` / `artifact/`) |
| PublishModelResults | The model is already registered; only the RDS write failed – publisher log `/aws/lambda/mmm-<env_short>-results-publisher`; re-invoke it with the same payload (execution history) once fixed |

## 3. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| `DatabricksExportError` 401/403 | Export service principal secret expired or rotated, or the IP access list blocks the NAT IPs | Update `mmm/<env>/databricks/export-sp` ([rotation.md](rotation.md)); WBD Databricks admins check the access list |
| `DatabricksExportError` no job id / 400 / 404 | `databricks_export_job_ids` missing the BU or `0`, or job deleted | WBD gives the job ID; set it in `terraform.tfvars` (PR) |
| `DatabricksExportFailed` | The WBD export job failed (source data, permissions on `raw/databricks/`) | [databricks-export-failed.md](databricks-export-failed.md) |
| `Glue.*` / `States.TaskFailed` on a Glue state | Job script error, Data Quality rule failed, out of memory, ENI / subnet IPs | [glue-job-failed.md](glue-job-failed.md) |
| Training / evaluation `States.TaskFailed` | Bad image, out of memory, empty snapshot | Job log; redeploy the training image ([deploy.md](deploy.md)) or raise `training_instance_type` |
| `ResourceLimitExceeded` | SageMaker quota | Service Quotas; retry ([scale-planning-season.md](scale-planning-season.md)) |

## 4. Re-run

1. Fix the root cause.
2. Start a refresh for the business unit (dev/staging any time; prod with a change ticket):

   ```bash
   scripts/trigger-model-refresh.sh <env> <business_unit>
   ```

3. Watch the new execution until `SUCCEEDED`. The new model package then waits for evaluation and
   approval in `model-governance.yml` ([model-rollback.md](model-rollback.md) for the reverse).

## 5. After

Record the execution ARN, the failing step and the root cause in the ticket. If the schedule must
pause (for example during a data outage), set `enable_model_refresh_schedule = false` through a PR.

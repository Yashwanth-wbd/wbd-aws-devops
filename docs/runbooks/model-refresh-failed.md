# Runbook: model refresh failed

A model refresh is one Step Functions execution of `mmm-<env>-model-refresh` per business unit,
started by EventBridge Scheduler (`mmm-<env_short>-refresh-<bu>`) or an `mmm.refresh` event
(`scripts/trigger-model-refresh.sh`). It runs the Databricks job (training snapshot), SageMaker
training, evaluation and registration (`PendingManualApproval`). Use this runbook when the
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
| StartDatabricksJob / GetDatabricksRun | EventBridge connection `mmm-<env>-databricks` (state `AUTHORIZED`); Databricks workspace → Jobs → run id from the execution history |
| DatabricksFailed | The Databricks job failed – data engineers own the job; snapshot path `s3://<training-data>/<bu>/<refresh_id>/` |
| TrainModel | CloudWatch `/aws/sagemaker/TrainingJobs`; console → SageMaker → Training jobs |
| EvaluateModel | CloudWatch `/aws/sagemaker/ProcessingJobs`; report `s3://<models>/evaluation/<bu>/<refresh_id>/evaluation.json` |
| RegisterModel | Model package group `mmm-<env_short>-<bu>` must exist (created by Terraform per BU) |

## 3. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| `States.Http.StatusCode.401/403` | Databricks service principal secret expired or rotated, or IP access list blocks Step Functions | Update the connection credentials ([rotation.md](rotation.md)); WBD Databricks admins check the access list |
| `States.Http.StatusCode.400/404` | Wrong `databricks_refresh_job_id` or job deleted | Fix the job id in `terraform.tfvars` (PR) |
| `DatabricksJobFailed` | Source data missing or the job's data-quality checks failed | Hand over to the data engineers with the Databricks run URL |
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

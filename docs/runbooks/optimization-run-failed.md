# Runbook: optimization run failed

An optimization run is asynchronous: the API starts Step Functions `mmm-<env>-optimization`, which
runs a SageMaker Processing job and calls the results publisher Lambda (alias `live`) to write the
summary into Aurora. Use this runbook when a run stays failed in the UI or the
`mmm-<env>-optimization-failed` alarm fires.

## 1. Find the execution

```bash
# From the app run id (UUID) or the UI
aws stepfunctions list-executions --state-machine-arn "$OPTIMIZATION_STATE_MACHINE_ARN" \
  --max-results 20 --query 'executions[?contains(name, `<run_id>`)]'

aws stepfunctions describe-execution --execution-arn <arn> \
  --query '{status:status,startDate:startDate,stopDate:stopDate,error:error,cause:cause}'

aws stepfunctions get-execution-history --execution-arn <arn> --reverse-order --max-results 30 \
  --query 'events[?type==`TaskFailed` || type==`ExecutionFailed`].[timestamp,type,executionFailedEventDetails,taskFailedEventDetails]'
```

GitHub Environment variable `OPTIMIZATION_STATE_MACHINE_ARN` (or `terraform output optimization`)
gives the ARN.

## 2. Where to look by step

| Step (state machine) | Logs / resources |
|---|---|
| GetOptimizerImage | SSM `/mmm/<env_short>/images/sagemaker-optimizer` – must be `<registry>/<repo>@<digest>`, not `:unset` |
| SageMaker Processing | CloudWatch `/aws/sagemaker/ProcessingJobs`, job name `mmm-<env_short>-opt-<run_id>`; console → SageMaker → Processing jobs |
| PublishResult / PublishFailure | Lambda `mmm-<env>-results-publisher`, log group `/aws/lambda/mmm-<env>-results-publisher` (alias `live`) |
| Input missing | S3 `s3://<results>/runs/<run_id>/input/` – API must upload before `StartExecution` |

Splunk (when enabled): same `run_id` across `/ecs/mmm-<env>/api`, `sfn-optimization`, publisher and
SageMaker job logs.

## 3. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| `States.TaskFailed` on SageMaker | Bad image, OOM, bad input JSON, missing curves | Processing job log; fix input or redeploy optimizer image ([deploy.md](deploy.md)) |
| Publisher Lambda error | DB/proxy unreachable, bad S3 output path, code bug | Publisher log; [ecs-task-stuck.md](ecs-task-stuck.md) if VPC-related |
| `AccessDenied` on S3 curves | Model not promoted for that BU | [model-rollback.md](model-rollback.md) or promote the approved package |
| Stuck `RUNNING` | SageMaker quota or capacity | Service quotas; retry after capacity returns |
| Deploy step "Optimization dry run" red (execution `dryrun-<run>-<attempt>`) | The new optimizer image or publisher does not handle `DRY_RUN` / `dry_run`, or one of the causes above | The release was rolled back automatically; look at the dry-run execution like any other run, fix, release again |

## 4. Re-run

1. Fix the root cause (image pointer, model curves, input file, publisher).
2. From the app, start a new optimization for the scenario (new `run_id`), **or** re-upload input to
   S3 and start execution manually (dev/staging only, with change ticket):

   ```bash
   aws stepfunctions start-execution --state-machine-arn "$OPTIMIZATION_STATE_MACHINE_ARN" \
     --name "manual-$(date -u +%Y%m%d%H%M%S)" \
     --input '{"run_id":"<uuid>","business_unit":"streaming","input_s3_uri":"s3://<results-bucket>/runs/<uuid>/input/request.json"}'
   ```

3. Watch `DescribeExecution` until `SUCCEEDED` or investigate the next failure.

Do not change a running execution's SageMaker job from the console; cancel with
`aws stepfunctions stop-execution` if the run must be abandoned.

## 5. After

If the failure was a bad release, roll back optimizer image and/or publisher ([rollback.md](rollback.md)).
Record the incident (run id, execution ARN, root cause) in the ticket.

# Runbook: optimization run failed

An optimization run is asynchronous: the API sends a request to the SQS queue
`mmm-<env>-optimization-requests`; the dispatcher Lambda `mmm-<env>-run-dispatcher` starts Step
Functions `mmm-<env>-optimization` (execution name = `run_id`) while fewer than
`max_concurrent_runs` runs are active; the state machine runs a SageMaker Processing job and calls
the results publisher Lambda (alias `live`) to write the summary into PostgreSQL. Use this runbook
when a run stays queued or failed in the UI, or one of `mmm-<env>-optimization-failed`,
`runs-dlq-not-empty`, `runs-dispatcher-errors`, `runs-dispatcher-throttles`,
`runs-oldest-request`, `runs-expired-requests` fires.

## 0. Run never started (still queued)

```bash
Q=$(aws sqs get-queue-url --queue-name $P-optimization-requests --query QueueUrl --output text)
aws sqs get-queue-attributes --queue-url "$Q" --attribute-names ApproximateNumberOfMessages \
  ApproximateNumberOfMessagesNotVisible ApproximateAgeOfOldestMessage
aws ssm get-parameter --name /mmm/$E/optimization/max_concurrent_runs --query Parameter.Value --output text
aws stepfunctions list-executions --state-machine-arn "$OPTIMIZATION_STATE_MACHINE_ARN" --status-filter RUNNING \
  --query 'length(executions)'
aws logs tail /aws/lambda/$P-run-dispatcher --since 30m
```

| Finding | Meaning / fix |
|---|---|
| RUNNING executions = `max_concurrent_runs`, log says `run slots busy` | Working as designed: the request waits (re-checked about every 6 minutes) and expires after `max_queue_wait_minutes` (`ExpiredRunRequests`, the planner resubmits). Many expiries → raise `max_concurrent_runs` ([scale-planning-season.md](scale-planning-season.md)) |
| Dispatcher log `invalid run request` | The API sent a body without `run_id` / `business_unit` / `input_s3_uri`, or a bad `run_id`; it lands in the DLQ after 10 tries. App team fixes the API |
| Dispatcher errors (`AccessDenied`, timeouts) | Check the dispatcher role and the `sqs` / `states` / `ssm` VPC endpoints; fix, then redrive the DLQ (below) |
| Old RUNNING executions that never finish | A stuck run holds a slot: stop it (`aws stepfunctions stop-execution`) |

**Redrive the DLQ** after the cause is fixed (requests older than `max_queue_wait_minutes` are
dropped by the dispatcher on arrival, so tell planners to resubmit those):

```bash
DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "$(aws sqs get-queue-url --queue-name $P-optimization-requests-dlq --query QueueUrl --output text)" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)
aws sqs start-message-move-task --source-arn "$DLQ_ARN"        # back to the source queue
aws sqs list-message-move-tasks --source-arn "$DLQ_ARN"
```

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
| Input missing | S3 `s3://<results>/runs/<run_id>/input/` – API must upload before it queues the request |

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
| Dry run `not started after 600s` | All run slots busy, or the dispatcher fails | Section 0 |

## 4. Re-run

1. Fix the root cause (image pointer, model curves, input file, publisher).
2. From the app, start a new optimization for the scenario (new `run_id`), **or** re-upload input to
   S3 and queue it manually (dev/staging only, with change ticket; the `run_id` must be new, a
   finished execution name cannot be reused):

   ```bash
   aws sqs send-message --queue-url "$OPTIMIZATION_QUEUE_URL" \
     --message-body '{"run_id":"manual-<yyyymmddhhmmss>","business_unit":"streaming","input_s3_uri":"s3://<results-bucket>/runs/<uuid>/input/request.json","requested_by":"<you>"}'
   ```

3. Watch `DescribeExecution` until `SUCCEEDED` or investigate the next failure.

Do not change a running execution's SageMaker job from the console; cancel with
`aws stepfunctions stop-execution` if the run must be abandoned.

## 5. After

If the failure was a bad release, roll back optimizer image and/or publisher ([rollback.md](rollback.md)).
Record the incident (run id, execution ARN, root cause) in the ticket.

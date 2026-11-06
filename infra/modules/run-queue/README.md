# run-queue

The optimization **run queue** (v3): planners' run requests wait in SQS and a small dispatcher
Lambda starts the optimization state machine only while fewer than `max_concurrent_runs` runs are
running. This protects the SageMaker quota and cost during the planning season and gives every
request a fair place in line.

**Status:** implemented (v3 architecture).

## Flow

```
API  --SendMessage-->  <prefix>-optimization-requests (SQS Standard, KMS)
                         |  event source: batch 10, max concurrency 2, ReportBatchItemFailures
                         v
                    <prefix>-run-dispatcher (Lambda, VPC)
                         |  reads SSM optimization/max_concurrent_runs, counts RUNNING executions
                         v
                    StartExecution name = run_id  ->  <prefix>-optimization (Step Functions)
```

| Case | What the dispatcher does |
|---|---|
| Slot free | `StartExecution` named `run_id`. A repeated delivery of the same request is a no-op (`ExecutionAlreadyExists`) |
| All slots busy | Returns the message as a batch-item failure; SQS delivers it again after the visibility timeout (6 × dispatcher timeout = 6 min) |
| Waited longer than `max_queue_wait_minutes` | Deletes it and publishes `ExpiredRunRequests` (namespace `MMM/Optimization`) - the planner resubmits |
| Invalid body | Batch-item failure; after `max_receive_count` (10) receives it lands in the DLQ |
| StartExecution error | Batch-item failure (retried; DLQ after 10 receives) |

The limit is a **soft limit**: two dispatcher invocations can run at the same time, so at most one
extra batch can start. The dispatcher also publishes `RunningRuns` for the dashboard.

## Message contract (API team)

```json
{"run_id": "r-20260601-0001", "business_unit": "usnetworks",
 "input_s3_uri": "s3://<results-bucket>/runs/r-20260601-0001/input/", "requested_by": "jdoe@wbd.com",
 "dry_run": false}
```

`run_id` = 1-80 characters `[A-Za-z0-9_-]` (it becomes the execution name). The API writes the input
to S3 first, then sends the message, and shows the run as **queued** until `DescribeExecution` on
`<state machine ARN with :execution:>…:<run_id>` returns a status.

## What it creates

| Resource | Name | Notes |
|---|---|---|
| SQS queue | `<prefix>-optimization-requests` | Standard, SSE-KMS (`sqs` key), visibility 6 × timeout, retention 4 days, long polling 20 s, TLS-only policy |
| SQS DLQ | `<prefix>-optimization-requests-dlq` | Retention 14 days; redrive allowed only from the main queue |
| Lambda | `<prefix>-run-dispatcher` | Python 3.12, code in `lambda/handler.py` (shipped by Terraform), reserved concurrency 2, VPC, X-Ray |
| Event source mapping | – | Batch 10, window 5 s, maximum concurrency 2, partial batch responses |
| Alarms | `<prefix>-runs-*` | `oldest-request` (> 15 min), `dlq-not-empty`, `dispatcher-errors`, `dispatcher-throttles`, `expired-requests` |

Redrive after a fix: `aws sqs start-message-move-task --source-arn <dlq_arn>` (runbook
`optimization-run-failed`).

## Checkov skips (with reason)

| Check | Reason |
|---|---|
| `CKV_AWS_272` | Code signing needs AWS Signer profiles from WBD; the zip is built from Git. |
| `CKV_AWS_116` | SQS event source: failures stay on the queue and go to its DLQ. |
| `CKV_AWS_356`, `CKV_AWS_111` | ENI, X-Ray and PutMetricData have no resource-level permissions (PutMetricData is limited by namespace). |

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | e.g. `mmm-dev` |
| `state_machine_arn`, `state_machine_name` | – | Optimization state machine |
| `max_runs_parameter_name`, `max_runs_parameter_arn` | – | SSM `optimization/max_concurrent_runs` |
| `max_queue_wait_minutes` | `30` | Expiry of a waiting request |
| `max_receive_count` | `10` | Receives before the DLQ |
| `dispatcher_timeout` | `60` | Seconds |
| `dispatcher_concurrency` | `2` | Reserved concurrency = event source maximum concurrency |
| `oldest_message_alarm_minutes` | `15` | |
| `metric_namespace` | `MMM/Optimization` | |
| `sqs_kms_key_arn`, `env_kms_key_arn`, `logs_kms_key_arn` | – | kms module |
| `log_retention_days` | `30` | |
| `subnet_ids`, `security_group_id` | – | Private-app subnets, `lambda` security group |
| `alarm_topic_arn`, `permissions_boundary_arn` | – | |

## Outputs

`queue_url`, `queue_arn`, `queue_name`, `dlq_url`, `dlq_arn`, `dlq_name`, `dispatcher_function_name`,
`log_group_name`, `alarm_names`.

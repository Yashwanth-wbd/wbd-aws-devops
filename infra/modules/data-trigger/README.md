# data-trigger

Starts **one** MWAA DAG run (`mmm_ingest`) when a file lands in the landing bucket, or when
someone asks for an on-demand refresh.

**Status:** implemented in Step 13 (created only when `enable_data_platform = true`).

```text
S3 landing  <bu>/...  --Object Created-->  EventBridge rule  mmm-<env>-data-trigger-landing  --+
scripts/trigger-ondemand.sh  --mmm.ondemand-->  rule  mmm-<env>-data-trigger-ondemand  -------+--> Lambda --> MWAA InvokeRestApi
                                                                                                         POST /dags/mmm_ingest/dagRuns
failed delivery / invocation -->  SQS  mmm-<env>-data-trigger-dlq  --> alarm
```

## How "exactly one run" works

The Lambda builds the `dag_run_id` from the event:

| Trigger | `dag_run_id` |
|---|---|
| File landed | `s3__<sha256(bucket, key, etag)[:32]>`: the same file version always gives the same ID |
| On demand | `ondemand__<sha256(request_id)[:32]>` |

EventBridge delivers at least once and retries. If the same event comes again, Airflow answers
**409 (run already exists)** and the Lambda logs `duplicate` and succeeds. So no DynamoDB table
is needed. A new version of the same file (new etag) is a new run.

Ignored: keys ending in `/` (folder markers) and keys outside `<business_unit>/`.

## What it creates

| Resource | Notes |
|---|---|
| Lambda `mmm-<env>-data-trigger` | Python 3.12, in the private-app subnets (`data_trigger` SG, HTTPS out through NAT), X-Ray, KMS-encrypted environment, reserved concurrency 5 |
| IAM role `mmm-<env>-data-trigger-lambda` | Permission boundary; `airflow:InvokeRestApi` on the **Airflow `User` role of this environment only** |
| EventBridge rules `-landing`, `-ondemand` | Targets retry for 1 h (10 attempts), then go to the DLQ |
| SQS `mmm-<env>-data-trigger-dlq` | KMS (`sqs` key), 14 days; the Lambda's own async failures go there too |
| Log group `/aws/lambda/mmm-<env>-data-trigger` | KMS (`logs` key) |
| Alarms `-errors`, `-dlq-not-empty` | To the alert topic |

The Lambda code is `lambda/handler.py`. Terraform zips it (`archive` provider), so no build
step is needed. The DAG run `conf` it sends:

```json
{"trigger": "s3", "environment": "dev", "business_unit": "usnetworks",
 "source": {"bucket": "wbd-mmm-dev-landing-use1", "key": "usnetworks/2026/11/spend.csv", "etag": "…", "size": 1234},
 "event_time": "2026-11-04T10:00:00Z"}
```

On demand: `{"trigger": "ondemand", "business_unit": "all|<bu>", "request_id", "requested_by", "reason", …}`.

## Inputs

| Name | Type | Default |
|---|---|---|
| `name_prefix`, `environment` | string | – |
| `landing_bucket_name` | string | – |
| `business_units` | list(string) | – |
| `mwaa_environment_name`, `airflow_role_arn` | string | – |
| `dag_id` | string | `mmm_ingest` |
| `ondemand_source` / `ondemand_detail_type` | string | `mmm.ondemand` / `Data refresh requested` |
| `subnet_ids`, `security_group_id` | list / string | – |
| `reserved_concurrency` | number | `5` |
| `lambda_kms_key_arn`, `sqs_kms_key_arn`, `logs_kms_key_arn` | string | – |
| `log_retention_days` | number | `30` |
| `alarm_topic_arn`, `permissions_boundary_arn` | string | – |

## Outputs

`function_name`, `log_group_name`, `dlq_url`, `rule_names`, `ondemand_event`.

## Alternative to confirm with WBD

Databricks Workflows **file-arrival triggers** could replace MWAA + Lambda if WBD prefers
orchestration inside Databricks. The landing bucket and the per-BU keys stay the same.

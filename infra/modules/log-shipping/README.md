# log-shipping

Sends CloudWatch Logs to WBD Splunk through Amazon Data Firehose.

**Status:** implemented in Step 9. It is off (`enabled = false`) until WBD provides the HEC
endpoint and token.

## Flow

```text
log groups ──subscription filter──> Firehose mmm-<env>-splunk ──HTTPS──> Splunk HEC
                                         │ decompress (gzip)          (token read from
                                         └─ failed records ─> S3        Secrets Manager)
                                            logs bucket/splunk-failed/
```

## What it creates (only when `enabled = true`)

| Resource | Name | Notes |
|---|---|---|
| Firehose stream | `<prefix>-splunk` | Encrypted with the logs KMS key. Buffers 60 s or 5 MB. Retries for 5 minutes, then the record goes to S3. Waits up to 180 s for HEC acknowledgements. |
| HEC token | – | **Read by Firehose from Secrets Manager** (`mmm/<env>/splunk/hec`). It is never a Terraform variable, never in the state, and never in CI. |
| Processing | – | Decompresses the CloudWatch Logs records. With `extract_messages = true`, only the log lines are sent, without the envelope. |
| Firehose role | `<prefix>-firehose-splunk` | Writes failed records, reads the HEC secret, writes its own error log. Permission boundary attached. |
| Error log group | `/aws/kinesisfirehose/<prefix>-splunk` | Stream `DestinationDelivery`: the reason Splunk refused a record. |
| CloudWatch Logs role | `<prefix>-logs-to-firehose` | Used by the subscription filters to put records on the stream. |
| Subscription filters | `<prefix>-splunk` on each log group | All events (empty filter pattern). |
| Alarms | `<prefix>-splunk-delivery`, `<prefix>-splunk-freshness` | Success < 99 %, or data older than 15 minutes, both to the alert topic. |

## Which logs (dev)

| Key | Log group | Why |
|---|---|---|
| `api`, `ui`, `migrate` | `/ecs/mmm-dev/<service>` | App logs with `run_id` |
| `ecs-exec` | `/ecs/mmm-dev/exec-audit` | Audit: commands typed in ECS Exec |
| `aurora-postgres` | `/aws/rds/cluster/mmm-dev-aurora/postgresql` | Audit: pgaudit, connections, errors |
| `waf` | `aws-waf-logs-mmm-dev` | Security: regional WAF on the ALB |
| `sfn-optimization`, `sfn-model-refresh` | `/aws/states/mmm-dev-<name>` | Run orchestration (model refresh with the data platform) |
| `publisher` | `/aws/lambda/mmm-dev-results-publisher` | Results written to Aurora per `run_id` |
| `sagemaker-jobs`, `sagemaker-train` | `/aws/sagemaker/ProcessingJobs`, `/aws/sagemaker/TrainingJobs` | Optimizer / evaluation and training job logs |
| `llm-*` | LLM gateway proxy and access logs | Only with GenAI |
| `vpc-flow` | `/aws/vpc/mmm-dev/flow-logs` | Only with `ship_vpc_flow_logs = true` (high volume and Splunk licence cost) |

## What the WBD Splunk team provides and configures

1. A **HEC endpoint** reachable over HTTPS from the
   [Firehose IP ranges](https://docs.aws.amazon.com/firehose/latest/dev/controlling-access.html#using-iam-splunk-vpc)
   of the region, with a CA-signed certificate. Firehose does not accept self-signed certificates.
2. A **HEC token with indexer acknowledgement on**, plus the index and the source type. Records
   are CloudWatch Logs JSON envelopes (`logGroup`, `logStream`, `logEvents[]`); the Splunk Add-on
   for Amazon Data Firehose parses them.
3. DevOps stores the token. It is never typed into a command line:

   ```powershell
   # hec.json = {"hec_token":"<token from WBD Splunk>"}
   aws secretsmanager put-secret-value --secret-id mmm/dev/splunk/hec --secret-string file://hec.json
   Remove-Item hec.json
   ```

   Firehose requires the key to be named exactly `hec_token`.
4. Set `splunk_hec_endpoint` and `enable_splunk_shipping = true` in tfvars, then apply.

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | |
| `enabled` | `false` | |
| `hec_endpoint`, `hec_endpoint_type` | –, `Raw` | |
| `hec_secret_arn`, `secrets_kms_key_arn` | – | `mmm/<env>/splunk/hec` and its key |
| `log_group_names` | – | key → log group name (same region) |
| `extract_messages` | `false` | |
| `failed_records_bucket_arn`, `failed_records_prefix` | –, `splunk-failed` | |
| `logs_kms_key_arn` | – | |
| `log_retention_days` | `365` | |
| `permissions_boundary_arn` | – | |
| `alert_topic_arn` | – | `module.monitoring.alert_topic_arn` |
| `tags` | `{}` | |

## Outputs

`delivery_stream_name`, `delivery_stream_arn` (both `null` while disabled), `shipped_log_groups`.

# monitoring

Alerts, alarms, event alerts, the platform dashboard, and masking of secrets in logs.

**Status:** implemented in Step 9.

## What it creates

| Resource | Name | Notes |
|---|---|---|
| KMS key | `alias/<prefix>-alerts` | Its own key, because CloudWatch and EventBridge must be named in the key policy to publish to an encrypted topic. |
| SNS topic | `<prefix>-alerts` | KMS-encrypted, TLS only. Only this account's alarms and EventBridge rules may publish. Email subscriptions come from `alert_emails`. |
| Metric alarms | `<prefix>-<name>` | See below. Each sends ALARM **and** OK to the topic. |
| EventBridge rules | `<prefix>-<name>` | ECS deployment failed, ECS service error, GuardDuty high. The message is a readable sentence (input transformer). |
| Dashboard | `<prefix>-platform` | The alarm list, then API, ECS, queue, job duration, RDS, Redis, WAF and CloudFront. |
| Logs data protection policy | `<prefix>-data-protection` | Account level. It masks AWS secret keys, private keys and card numbers in **every** log group. |

## Alarms

| Alarm | Fires when | First thing to check |
|---|---|---|
| `api-5xx-rate` | Target + ALB 5xx > 2 % of requests in 3 of 5 minutes (only at ≥ 20 requests / min) | API logs, the last deploy |
| `api-no-healthy-targets` | No healthy API task for 2 minutes | ECS service events, the `/api/health` response |
| `queue-oldest-job` | Oldest job waits > 5 minutes | Worker running count, worker logs |
| `dlq-not-empty` | Any job in the DLQ (failed 3 times) | Worker logs for that job, then redrive (see the `sqs` README) |
| `rds-cpu` | RDS CPU > 80 % for 15 minutes | Performance Insights, top SQL |
| `rds-free-storage` | Free storage < 5 GiB in dev, 20 GiB in staging and prod | Storage autoscaling maximum |
| `redis-cpu-<node>`, `redis-memory-<node>` | Engine CPU or memory > 80 % | Key sizes and TTLs, node type |
| `whatif-p95` | What-if p95 > 10 s in 3 of 5 minutes | What-if worker logs and CPU |
| `cert-expiry-<name>` | ACM certificate expires in < 30 days | The ACM renewal status: usually a missing DNS validation record |
| `splunk-delivery`, `splunk-freshness` | From the `log-shipping` module | Firehose error log |

Event alerts:

| Rule | Fires when |
|---|---|
| `ecs-deployment-failed` | A deployment failed and the circuit breaker rolled it back |
| `ecs-service-error` | ECS cannot start or place tasks, for example the image pull or a secret failed |
| `guardduty-high` | A GuardDuty finding with severity ≥ 7 (`enable_guardduty_alerts`). GuardDuty itself is WBD's baseline. |

Budget alerts come from the `budgets` module (Step 3) and are emailed directly.

## App contract (for the backend team)

The alarms and the "one `run_id` across API, worker and audit" search in Splunk need the services
to do two things:

**1. Log one JSON object per line to stdout** with at least these fields:

```json
{"ts":"2026-11-03T10:15:00Z","level":"INFO","service":"api","env":"dev","run_id":"r-123","scenario_id":"s-42","job_id":"j-9","user":"<okta sub>","bu":"streaming","msg":"job queued"}
```

The API creates `run_id` and sends it as a message attribute on the SQS job. The worker logs the
same `run_id`, and the audit rows in PostgreSQL store it too. **Never log tokens, passwords or
the `Authorization` header.** The data protection policy is only a safety net.

**2. Publish job durations with CloudWatch Embedded Metric Format** (a log line; no API call or
extra IAM needed):

```json
{"_aws":{"Timestamp":1793712000000,"CloudWatchMetrics":[{"Namespace":"MMM","Dimensions":[["Environment"]],"Metrics":[{"Name":"WhatIfDurationMs","Unit":"Milliseconds"}]}]},"Environment":"dev","WhatIfDurationMs":2300,"run_id":"r-123"}
```

Metric names: `WhatIfDurationMs` (alarm and dashboard) and `OptimizeDurationMs` (dashboard).
Until the app publishes them, `whatif-p95` stays `INSUFFICIENT_DATA`, which is expected.

## Application Signals

Container Insights (enhanced) is on in the cluster (Step 7). Application Signals (service map,
SLOs) needs the services' `enable_application_signals = true`, plus a one-time account switch:

```powershell
aws application-signals start-discovery
```

## Inputs (main ones)

| Name | Default | Description |
|---|---|---|
| `name_prefix`, `environment` | – | |
| `alert_emails` | `[]` | Each address must click the confirmation email |
| `alb_arn_suffix`, `api_target_group_arn_suffix` | – | From `alb` |
| `queue_name`, `dlq_name` | – | From `sqs` |
| `rds_instance_id`, `redis_node_ids` | – | |
| `ecs_cluster_name`, `ecs_service_names` | – | |
| `certificate_arns` | `{}` | name → ARN, in **this** region only |
| `waf_web_acl_name`, `cloudfront_distribution_id` | `null` | Dashboard widgets in us-east-1 |
| Thresholds | see `variables.tf` | `api_5xx_percent_threshold` 2, `queue_oldest_age_seconds` 300, `rds_cpu_percent` 80, `rds_free_storage_gib` 10, `redis_percent` 80, `whatif_p95_ms` 10000, `certificate_days_to_expiry` 30 |
| `app_metric_namespace` | `MMM` | |
| `enable_guardduty_alerts` | `true` | |
| `enable_log_data_protection` | `true` | Only one account-level policy is allowed. Set `false` if WBD already has one. |
| `data_protection_identifiers` | secret keys, private keys, card numbers | Emails are left out on purpose: user emails in audit logs must stay readable. |

## Outputs

`alert_topic_arn`, `alarm_names`, `event_rule_names`, `dashboard_name`.

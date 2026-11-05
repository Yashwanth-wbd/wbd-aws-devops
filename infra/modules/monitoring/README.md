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
| Dashboard | `<prefix>-platform` | The alarm list, then API, ECS, what-if duration, Aurora CPU / connections / ACU, Step Functions executions, Lambda, regional WAF. |
| Logs data protection policy | `<prefix>-data-protection` | Account level. It masks AWS secret keys, private keys and card numbers in **every** log group. |

## Alarms

| Alarm | Fires when | First thing to check |
|---|---|---|
| `api-5xx-rate` | Target + ALB 5xx > 2 % of requests in 3 of 5 minutes (only at ≥ 20 requests / min) | API logs, the last deploy |
| `ui-no-healthy-targets`, `api-no-healthy-targets` | No healthy task in that target group for 2 minutes | ECS service events, the health check response |
| `aurora-cpu` | Aurora CPU > 80 % for 15 minutes | Performance Insights, top SQL |
| `aurora-acu-max` | ACU utilization > 90 % of `max_acu` | Performance Insights; raise `aurora_max_acu` |
| `whatif-p95` | What-if p95 > 10 s in 3 of 5 minutes | API logs and CPU (what-if runs in the API) |
| `<state machine>-failed` | From the `step-functions` module | Failed execution in the console, then the SageMaker job log |
| `<function>-errors` | From the `lambda-function` module | Function log |
| `cert-expiry-<name>` | ACM certificate expires in < 30 days | The ACM renewal status: usually a missing DNS validation record |
| `splunk-delivery`, `splunk-freshness` | From the `log-shipping` module | Firehose error log |

Event alerts:

| Rule | Fires when |
|---|---|
| `ecs-deployment-failed` | A deployment failed and the circuit breaker rolled it back |
| `ecs-service-error` | ECS cannot start or place tasks, for example the image pull or a secret failed |
| `guardduty-high` | A GuardDuty finding with severity ≥ 7 (`enable_guardduty_alerts`). GuardDuty itself is WBD's baseline. |
| `breakglass-used` | Console sign-in or change by the `BreakGlass` permission set (`enable_breakglass_alert`, prod; API calls need the WBD CloudTrail trail). Step 15 |

Budget alerts come from the `budgets` module (Step 3) and are emailed directly.

## App contract (for the backend team)

The alarms and the "one `run_id` across API, worker and audit" search in Splunk need the services
to do two things:

**1. Log one JSON object per line to stdout** with at least these fields:

```json
{"ts":"2026-11-03T10:15:00Z","level":"INFO","service":"api","env":"dev","run_id":"r-123","scenario_id":"s-42","job_id":"j-9","user":"<okta sub>","bu":"streaming","msg":"job queued"}
```

The API creates `run_id` and passes it as the Step Functions execution input. The optimizer job and
the results publisher log the same `run_id`, and the audit rows in Aurora store it too. **Never log tokens, passwords or
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
| `alb_arn_suffix`, `target_group_arn_suffixes` | – | From `alb` (map must contain `api`) |
| `aurora_cluster_id` | – | From `aurora` |
| `state_machine_arns`, `lambda_function_names` | – | Dashboard widgets |
| `ecs_cluster_name`, `ecs_service_names` | – | |
| `certificate_arns` | `{}` | name → ARN, in **this** region only |
| `waf_web_acl_name` | `null` | Regional web ACL (dashboard) |
| Thresholds | see `variables.tf` | `api_5xx_percent_threshold` 2, `aurora_cpu_percent` 80, `aurora_acu_percent` 90, `whatif_p95_ms` 10000, `certificate_days_to_expiry` 30 |
| `app_metric_namespace` | `MMM` | |
| `enable_guardduty_alerts` | `true` | |
| `enable_breakglass_alert` | `false` | prod stack sets `true` |
| `breakglass_permission_set` | `BreakGlass` | IAM Identity Center permission set name |
| `enable_log_data_protection` | `true` | Only one account-level policy is allowed. Set `false` if WBD already has one. |
| `data_protection_identifiers` | secret keys, private keys, card numbers | Emails are left out on purpose: user emails in audit logs must stay readable. |

## Outputs

`alert_topic_arn`, `alarm_names`, `event_rule_names`, `dashboard_name`.

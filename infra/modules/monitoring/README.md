# monitoring

Alerts, alarms, event alerts, the platform dashboard, and masking of secrets in logs.

**Status:** implemented in Step 9.

## What it creates

| Resource | Name | Notes |
|---|---|---|
| KMS key | `alias/<prefix>-alerts` | Its own key, because CloudWatch and EventBridge must be named in the key policy to publish to an encrypted topic. |
| SNS topic | `<prefix>-alerts` | KMS-encrypted, TLS only. Only this account's alarms and EventBridge rules may publish. Email subscriptions come from `alert_emails`. |
| Metric alarms | `<prefix>-<name>` | See below. Each sends ALARM **and** OK to the topic. |
| EventBridge rules | `<prefix>-<name>` | ECS deployment failed, ECS service error, GuardDuty high, break-glass. The message is a readable sentence (input transformer). |
| Dashboards | `<prefix>-<name>` | See below. |
| Logs data protection policy | `<prefix>-data-protection` | Account level. It masks AWS secret keys, private keys and card numbers in **every** log group. |

## Alarms

| Alarm | Fires when | First thing to check |
|---|---|---|
| `api-5xx-rate` | Target + ALB 5xx > 2 % of requests in 3 of 5 minutes (only at ≥ 20 requests / min) | API logs, the last deploy |
| `availability` | Less than 99.5 % of the last hour's ALB requests (UI + API) without a 5xx (only at ≥ 100 requests / hour; all hours, not only business hours) | `api-5xx-rate`, health alarms, the last deploy |
| `ui-no-healthy-targets`, `api-no-healthy-targets` | No healthy task in that target group for 2 minutes | ECS service events, the health check response |
| `rds-cpu` | RDS CPU > 80 % for 15 minutes | Performance Insights, top SQL; a larger `rds_instance_class` |
| `rds-free-storage` | Free storage < `rds_free_storage_gib` (about 10 % of the allocated storage) for 15 minutes | Storage autoscaling may be at `rds_max_allocated_storage` - raise it |
| `rds-connections` | Connections > 80 % of `max_connections` of the instance class for 10 minutes (`rds_max_connections`) | RDS Proxy pool, API task count |
| `rds-read-latency`, `rds-write-latency` | Average latency > 20 ms for 15 minutes | IOPS on the RDS dashboard, slow queries |
| `runs-*` | From the `run-queue` module: oldest request > 15 min, DLQ not empty, dispatcher errors / throttles, expired requests | `runbooks/optimization-run-failed.md` |
| `model-drift-<bu>`, `model-monitor-failed` | Drift score above `model_drift_threshold` (stack `data.tf`); drift check failed (`step-functions` module) | `runbooks/model-drift.md` |
| `whatif-p95` | What-if p95 > 10 s in 3 of 5 minutes | API logs and CPU (what-if runs in the API) |
| `optimization-runtime-max` | An optimization execution took > 10 minutes (the large-run limit) | SageMaker job log; `optimizer_instance_type` |
| `optimization-standard-p95` | Standard runs p95 > 2 minutes (app metric, below) | SageMaker job log; `optimizer_instance_type` |
| `model-refresh-overdue` | No successful model refresh for 7 days (data platform with the scheduled refresh on) | `runbooks/model-refresh-failed.md` |
| `<state machine>-failed`, `<state machine>-throttled` | From the `step-functions` module | Failed execution in the console, then the SageMaker job log; throttling: Step Functions quota |
| `<function>-errors` | From the `lambda-function` module | Function log |
| `llm-gateway-5xx`, `-4xx`, `-latency-p95`; `genai-tokens-<bu>` | From the `llm-gateway` module; token quota alarms (80 % of `genai_token_quotas`) in the stack's `genai.tf` | `runbooks/genai.md` |
| `cert-expiry-<name>` | ACM certificate expires in < 30 days | The ACM renewal status: usually a missing DNS validation record |
| `splunk-delivery`, `splunk-freshness` | From the `log-shipping` module | Firehose error log |

Event alerts:

| Rule | Fires when |
|---|---|
| `ecs-deployment-failed` | A deployment failed and the circuit breaker rolled it back |
| `ecs-service-error` | ECS cannot start or place tasks, for example the image pull or a secret failed |
| `guardduty-high` | A GuardDuty finding with severity ≥ 7 (`enable_guardduty_alerts`). GuardDuty itself is WBD's baseline. |
| `breakglass-used` | Console sign-in or change by the `BreakGlass` permission set (`enable_breakglass_alert`, prod; API calls need the WBD CloudTrail trail). Step 15 |

Budget alerts come from the `budgets` module (Step 3) and are emailed directly. Backup job
failures come from the `backup` module (EventBridge `backup-job-failed`). Model versions that are
created, approved or rejected (failed `data/model-thresholds.yaml`, rollback) come from the
`sagemaker` module (EventBridge `model-package-state`, data platform).

Not separate alarms on purpose: SageMaker job failures fail the state machine (`-failed`), and the
results publisher is invoked synchronously by Step Functions (retries, then `PublishFailure`), so
it has no dead-letter queue. Run requests that cannot be started end in the run queue's DLQ
(`runs-dlq-not-empty`).

## Dashboards

| Dashboard | Shows |
|---|---|
| `<prefix>-platform` | The alarm list, requests and 5xx (UI + API), ECS tasks, RDS CPU / connections, Step Functions, Lambda, regional WAF |
| `<prefix>-api-ui` | API requests / 4xx / 5xx and latency, UI requests / 5xx, ECS CPU and memory, what-if p95 |
| `<prefix>-optimization` | Executions (started, succeeded, failed, timed out, throttled), execution time, run duration by size, results publisher, run queue (waiting, DLQ, oldest request, running runs, expired requests) |
| `<prefix>-training` | Model-refresh and model-monitor executions, drift score per business unit (data platform) |
| `<prefix>-rds` | CPU, connections, free storage, memory, read / write latency, IOPS, RDS Proxy connections |
| `<prefix>-cost` | Estimated charges, total and by service (us-east-1 billing metrics; needs "Receive Billing Alerts" on in the account) |
| `<prefix>-genai` | LLM gateway requests, 4xx / 5xx, latency, tokens per BU (`enable_genai`) |

## App contract (for the backend team)

The alarms and the "one `run_id` across API, optimizer job and audit" search in Splunk need the services
to do two things:

**1. Log one JSON object per line to stdout** with at least these fields:

```json
{"ts":"2026-11-03T10:15:00Z","level":"INFO","service":"api","env":"dev","run_id":"r-123","scenario_id":"s-42","job_id":"j-9","user":"<okta sub>","bu":"streaming","msg":"job queued"}
```

The API creates `run_id` and puts it in the run-queue message; the dispatcher uses it as the
Step Functions execution name and input. The optimizer job and
the results publisher log the same `run_id`, and the audit rows in RDS store it too. **Never log tokens, passwords or
the `Authorization` header.** The data protection policy is only a safety net.

**2. Publish job durations with CloudWatch Embedded Metric Format** (a log line; no API call or
extra IAM needed):

```json
{"_aws":{"Timestamp":1793712000000,"CloudWatchMetrics":[{"Namespace":"MMM","Dimensions":[["Environment"]],"Metrics":[{"Name":"WhatIfDurationMs","Unit":"Milliseconds"}]}]},"Environment":"dev","WhatIfDurationMs":2300,"run_id":"r-123"}
```

| Metric | Published by | Dimensions | Used by |
|---|---|---|---|
| `WhatIfDurationMs` | API | `Environment` | `whatif-p95`, api-ui dashboard |
| `OptimizeDurationMs` | results publisher (run end − run start) | `Environment`, `RunSize` = `standard` or `large` | `optimization-standard-p95`, optimization dashboard |
| `GenAITokens` | API (tokens of each LLM call) | `Environment`, `BusinessUnit` | `genai-tokens-<bu>`, genai dashboard |

Until the app publishes them, these alarms stay `INSUFFICIENT_DATA`, which is expected.

**3. Post-release dry run** (`scripts/dry-run-optimization.sh`, dev and staging): the optimizer
image gets `DRY_RUN=true` (only load the input and the approved curves, write a small output) and
the results publisher gets `"dry_run": true` (check the database connection, write no run).
Every normal run gets `DRY_RUN=false` / `"dry_run": false`.

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
| `rds_instance_id` | – | From `rds` |
| `state_machine_arns`, `lambda_function_names` | – | Dashboard widgets; keys `optimization` / `model-refresh` add their dashboard and alarms, `model-monitor` joins the training dashboard |
| `publisher_function_name`, `llm_gateway_api_name`, `genai_business_units` | `null` / `null` / `[]` | Optimization and GenAI dashboards |
| `run_queue_name`, `run_dlq_name` | `null` | Run queue widgets on the optimization dashboard |
| `drift_business_units` | `[]` | Drift score widget on the training dashboard |
| `rds_max_connections`, `rds_free_storage_gib` | `null`, `10` | Connections alarm (max_connections of the class) and free-storage alarm |
| `model_refresh_overdue_days` | `null` | Model refresh overdue alarm (data platform) |
| `ecs_cluster_name`, `ecs_service_names` | – | |
| `certificate_arns` | `{}` | name → ARN, in **this** region only |
| `waf_web_acl_name` | `null` | Regional web ACL (dashboard) |
| Thresholds | see `variables.tf` | `api_5xx_percent_threshold` 2, `availability_target_percent` 99.5, `rds_cpu_percent` 80, `rds_connections_percent` 80, `rds_latency_ms` 20, `whatif_p95_ms` 10000, `optimization_standard_p95_seconds` 120, `optimization_max_minutes` 10, `certificate_days_to_expiry` 30 |
| `app_metric_namespace` | `MMM` | |
| `enable_guardduty_alerts` | `true` | |
| `enable_breakglass_alert` | `false` | prod stack sets `true` |
| `breakglass_permission_set` | `BreakGlass` | IAM Identity Center permission set name |
| `enable_log_data_protection` | `true` | Only one account-level policy is allowed. Set `false` if WBD already has one. |
| `data_protection_identifiers` | secret keys, private keys, card numbers | Emails are left out on purpose: user emails in audit logs must stay readable. |

## Outputs

`alert_topic_arn`, `alarm_names`, `event_rule_names`, `dashboard_name` (platform), `dashboard_names`.

# budgets

Cost guard rails for one account.

**Status:** implemented in Step 3.

## What it creates

| Resource | Name (dev) | Behaviour |
|---|---|---|
| `aws_budgets_budget` | `mmm-dev-monthly` | Emails when **actual** spend passes 50 %, 80 % and 100 %, and when the month is **forecast** to pass 100 % |
| `aws_ce_anomaly_monitor` | `mmm-dev-services` | Watches spend per AWS service for unusual jumps |
| `aws_ce_anomaly_subscription` | `mmm-dev-anomalies` | Daily email for anomalies with ≥ `anomaly_threshold_usd` impact |

AWS allows only **one** service-level anomaly monitor per account. If WBD already has one in
these accounts, set `enable_anomaly_detection = false`.

In Step 9 the monitoring SNS topic can be passed as `sns_topic_arn`, so budget alerts also
reach the Teams channel.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | – | e.g. `mmm-dev` |
| `monthly_limit_usd` | number | – | Budget per month |
| `actual_thresholds_percent` | list(number) | `[50, 80, 100]` | Actual-spend alert levels |
| `alert_emails` | list(string) | – | Recipients |
| `sns_topic_arn` | string | `null` | Optional extra target |
| `enable_anomaly_detection` | bool | `true` | Create the anomaly monitor |
| `anomaly_threshold_usd` | number | `100` | Minimum impact to report |

## Outputs

| Name | Description |
|---|---|
| `budget_name` | Budget name |
| `anomaly_monitor_arn` | Monitor ARN or `null` |

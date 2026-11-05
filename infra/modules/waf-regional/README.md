# waf-regional

Regional AWS WAF web ACL on the public ALB. Replaces the CloudFront (global) WAF of v1.

**Status:** implemented (v2 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_wafv2_web_acl` `<prefix>-alb` | Rules in order: `geo-allow-list` (5, only when `geo_allow_countries` is set), AWS managed `IpReputationList` (10), `CommonRuleSet` (20, `count_only_rules` switched to count), `KnownBadInputs` (30), `SQLiRuleSet` (40), `rate-limit-per-ip` (50, `rate_limit` per 5 min). CloudWatch metrics per rule |
| `aws_wafv2_web_acl_association` | Attaches the ACL to `alb_arn` |
| `aws_cloudwatch_log_group` `aws-waf-logs-<prefix>` | KMS-encrypted; `authorization` and `cookie` headers are redacted. Shipped to Splunk |

Set `waf_count_only = true` in the stack for the first days of a new environment to observe
before blocking.

## Inputs

`name_prefix`, `alb_arn`, `rate_limit` (2000), `geo_allow_countries` ([]), `count_only_rules` ([]),
`logs_kms_key_arn`, `log_retention_days` (90), `tags`.

## Outputs

`web_acl_arn`, `web_acl_name` (monitoring dashboard), `log_group_name`.

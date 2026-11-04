# bedrock

Release 2 GenAI: Bedrock private endpoint, guardrail, invocation logging, alarms, dashboard and budget.
Used by `infra/environments/<env>/genai.tf` with `count = enable_genai ? 1 : 0`. Guide: [docs/12](../../../docs/12-genai-bedrock.md).

**Status:** implemented in Step 14.

## Resources

| File | Resources |
|---|---|
| `main.tf` | `aws_bedrock_guardrail` (prompt attack, content filters, PII anonymize / block, contextual grounding + relevance, profanity), `aws_bedrock_guardrail_version` (pinned, `skip_destroy`; new version when `guardrail_version_label` changes) |
| `endpoint.tf` | `bedrock-runtime` interface endpoint, private DNS; policy: only `invoker_role_arns`, only the approved model ARNs and the guardrail |
| `logging.tf` | `aws_bedrock_model_invocation_logging_configuration` (text only) → S3 bucket (nested `s3-bucket` module: versioning, KMS, TLS-only, access logs) + log group; logging role with the permission boundary. Behind `enable_invocation_logging` (one setting per account and region) |
| `monitoring.tf` | Per model: server errors, client errors, throttles, p95 latency alarms; 24 h token alarm on all models (sum of quotas) and per BU (gateway EMF metric `MMM/GenAI Tokens`); dashboard; monthly cost budget |

Model IDs that start with `us.`, `eu.`, `apac.`, `us-gov.` or `global.` are cross-region inference
profiles: the profile ARN and the base model in every region are allowed.

The KMS key (`kms_key_arn`) must let `bedrock.amazonaws.com` (`GenerateDataKey`, `Decrypt`, same
account) and CloudWatch Logs use it – the environment stack adds both to the `genai` key.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix`, `environment`, `tags` | Naming, metric dimension, extra tags | – |
| `approved_model_ids` | WBD-approved model IDs (at least one) | – |
| `kms_key_arn`, `permissions_boundary_arn` | `genai` key; boundary for the logging role | – |
| `vpc_id`, `endpoint_subnet_ids`, `endpoint_security_group_id` | Where the endpoint goes | – |
| `invoker_role_arns` | Roles allowed through the endpoint (gateway task role) | – |
| `guardrail_version_label` | Bump to publish a new version | `v1` |
| `prompt_attack_strength`, `content_filter_strength` | Filter strengths | `HIGH`, `MEDIUM` |
| `pii_anonymize_types`, `pii_block_types` | PII handling | email/phone/name/address; SSN/card/bank/AWS keys/password |
| `grounding_threshold`, `relevance_threshold` | Contextual grounding (0–0.99) | `0.75`, `0.75` |
| `blocked_input_message`, `blocked_output_message` | Texts returned when blocked | – |
| `enable_invocation_logging`, `invocation_log_bucket_name`, `invocation_log_prefix`, `invocation_log_s3_days`, `log_retention_days` | Invocation logging | `true`, –, `bedrock-invocations`, `400`, `90` |
| `access_log_bucket`, `access_log_prefix` | S3 access logs of the log bucket | – |
| `alert_topic_arn` | SNS topic for alarms | `null` |
| `ecs_cluster_name`, `gateway_service_name`, `gateway_log_group_name` | Dashboard widgets | – |
| `token_quotas` | Daily tokens per BU | `{}` |
| `server_error_threshold`, `client_error_threshold`, `throttle_threshold`, `latency_p95_ms` | Alarm thresholds (per 5 min, 3 periods) | `0`, `5`, `5`, `20000` |
| `monthly_budget_usd`, `budget_alert_emails`, `budget_service_names` | Cost budget | –, –, `["Amazon Bedrock"]` |

## Outputs

`guardrail_id`, `guardrail_arn`, `guardrail_version`, `model_arns`, `vpc_endpoint_id`,
`invocation_log_bucket`, `invocation_log_group`, `dashboard_name`, `alarm_names`, `budget_name`.

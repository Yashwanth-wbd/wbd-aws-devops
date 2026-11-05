# llm-gateway

Private API Gateway in front of the approved external LLM providers (OpenAI, Anthropic, Google).
The API task calls it with SigV4; the gateway adds the provider key from Secrets Manager and runs
every prompt and answer through the Bedrock guardrail. Only with `enable_genai`.
Details in [docs/12](../../../docs/12-genai-bedrock.md).

**Status:** implemented (v2 architecture). Replaces the v1 `bedrock` module and the
`genai-gateway` ECS service.

## What it creates

| Resource | Notes |
|---|---|
| `aws_api_gateway_rest_api` `<prefix>-llm-gateway` | Type `PRIVATE`, reachable only through the `execute-api` VPC endpoint. Resource policy: `invoker_role_arns` only, `AWS_IAM` auth on `ANY /{provider}/{proxy+}` |
| Stage `v1` | Throttling (`throttle_rate_per_second`, `throttle_burst`), JSON access logs (no bodies), X-Ray |
| `aws_lambda_function` proxy | VPC Lambda (genai SG, NAT egress). Forwards only to the configured `llm_providers` base URLs, sets the provider auth header from `provider_secret_arns`, calls `ApplyGuardrail` on input and output. `reserved_concurrency` cap |
| Account logging role | `aws_api_gateway_account` (skip with `manage_account_logging_role = false` if WBD already sets it) |
| `aws_cloudwatch_metric_alarm` 5xx | `error_alarm_threshold` per 5 minutes → `alarm_topic_arn` |

Provider keys (`mmm/<env>/llm/<provider>`, `{"api_key": "..."}`) are filled out of band by DevOps (docs/05).

## Inputs

`name_prefix`, `llm_providers`, `provider_secret_arns`, `guardrail_id`, `guardrail_arn`,
`guardrail_version`, `guardrail_kms_key_arn`, `invoker_role_arns`, `vpc_endpoint_id`, `subnet_ids`,
`security_group_id`, `secrets_kms_key_arn`, `logs_kms_key_arn`, `log_retention_days`,
`reserved_concurrency` (50), `throttle_rate_per_second` (20), `throttle_burst` (40),
`error_alarm_threshold` (5), `manage_account_logging_role` (true), `alarm_topic_arn`,
`permissions_boundary_arn`, `tags`.

## Outputs

`invoke_url` (the API's `LLM_GATEWAY_URL`), `rest_api_id`, `execution_arn` (already ends in `/v1/*/*`),
`proxy_function_name`, `log_group_names`, `alarm_names`.

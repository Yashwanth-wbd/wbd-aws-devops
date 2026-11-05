# ================================================================== Step 14 - Release 2 GenAI (LLM gateway)
# Everything here exists only with enable_genai = true.
# API task --SigV4--> private API Gateway (execute-api endpoint, resource policy: API role only)
#   -> proxy Lambda: Bedrock guardrail on the prompt -> approved provider (OpenAI / Anthropic / Google,
#      key from Secrets Manager llm/<provider>) -> guardrail on the answer.
# Sending data to an external provider needs WBD data-egress approval first (docs/11).
# The user-facing switch is the genai_enabled SSM flag.
locals {
  genai_count = var.enable_genai ? 1 : 0

  # Private API Gateway and the guardrail (ApplyGuardrail) stay inside the VPC.
  genai_interface_endpoints = var.enable_genai ? ["execute-api", "bedrock-runtime"] : []
}

# ------------------------------------------------------------------ Bedrock guardrail
module "guardrails" {
  source = "../../modules/bedrock-guardrails"
  count  = local.genai_count

  name_prefix         = local.name_prefix
  kms_key_arn         = module.kms.key_arns["genai"]
  version_label       = var.genai_guardrail_version_label
  grounding_threshold = var.genai_grounding_threshold
  relevance_threshold = var.genai_relevance_threshold
  alarm_topic_arn     = module.monitoring.alert_topic_arn
}

# ------------------------------------------------------------------ LLM gateway
module "llm_gateway" {
  source = "../../modules/llm-gateway"
  count  = local.genai_count

  name_prefix          = local.name_prefix
  llm_providers        = var.llm_providers
  provider_secret_arns = { for p in keys(var.llm_providers) : p => module.secrets.secret_arns["llm/${p}"] }

  guardrail_id          = module.guardrails[0].guardrail_id
  guardrail_arn         = module.guardrails[0].guardrail_arn
  guardrail_version     = module.guardrails[0].guardrail_version
  guardrail_kms_key_arn = module.kms.key_arns["genai"]

  invoker_role_arns = [local.api_task_role_arn]
  vpc_endpoint_id   = module.network.interface_endpoint_ids["execute-api"]
  subnet_ids        = module.network.private_app_subnet_ids
  security_group_id = module.network.security_group_ids["genai"]

  secrets_kms_key_arn = module.kms.key_arns["secrets"]
  logs_kms_key_arn    = module.kms.key_arns["logs"]
  log_retention_days  = var.log_retention_days

  reserved_concurrency        = var.genai_reserved_concurrency
  manage_account_logging_role = var.manage_apigw_account_logging_role

  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Token quota (80 % of the daily quota per BU)
# The API enforces the quota (SSM genai/token_quota/<bu>) and publishes GenAITokens with Embedded
# Metric Format (dimensions Environment, BusinessUnit; modules/monitoring README "App metric contract").
resource "aws_cloudwatch_metric_alarm" "genai_token_quota" {
  for_each = var.enable_genai ? var.genai_token_quotas : {}

  alarm_name          = "${local.name_prefix}-genai-tokens-${each.key}"
  alarm_description   = "GenAI tokens of BU ${each.key} > 80% of the daily quota (${each.value}) - raise genai_token_quotas or check for misuse"
  namespace           = "MMM"
  metric_name         = "GenAITokens"
  dimensions          = { Environment = var.environment, BusinessUnit = each.key }
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = floor(each.value * 0.8)
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.monitoring.alert_topic_arn]
  ok_actions          = [module.monitoring.alert_topic_arn]
}

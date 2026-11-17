# ================================================================== Step 14 - Release 2 GenAI (Amazon Bedrock)
# Everything here exists only with enable_genai = true.
# API task --SigV4--> bedrock-runtime VPC endpoint -> Amazon Bedrock Converse / InvokeModel with
# guardrailConfig (pinned guardrail on the prompt and the answer). No API Gateway, no proxy, no API keys.
# Models: genai_model_ids[0] is the default (Anthropic Claude); the others (OpenAI / Google on Bedrock)
# are optional, for experimentation. The API role may invoke only these models, and only with the
# guardrail (IAM condition bedrock:GuardrailIdentifier).
# The user-facing switch is the genai_enabled SSM flag.
locals {
  genai_count = var.enable_genai ? 1 : 0

  genai_interface_endpoints = var.enable_genai ? ["bedrock-runtime"] : []

  genai_default_model_id = var.genai_model_ids[0]

  # A cross-region (system) inference profile ID has a geography prefix (us.anthropic....); Bedrock then
  # checks the profile ARN and the foundation model in every region of the profile.
  genai_models = {
    for id in var.genai_model_ids : id => {
      profile    = can(regex("^(us|us-gov|eu|apac|ca|jp|au|global)\\.", id))
      base_model = can(regex("^(us|us-gov|eu|apac|ca|jp|au|global)\\.", id)) ? join(".", slice(split(".", id), 1, length(split(".", id)))) : id
    }
  }

  genai_model_arns = flatten([
    for id, m in local.genai_models : m.profile ? [
      "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/${id}",
      "arn:${local.partition}:bedrock:*::foundation-model/${m.base_model}",
    ] : ["arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/${id}"]
  ])

  genai_bu_profiles = var.enable_genai && var.enable_genai_bu_inference_profiles ? toset(var.business_units) : toset([])
  genai_default_model_source_arn = local.genai_models[local.genai_default_model_id].profile ? (
    "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/${local.genai_default_model_id}"
  ) : "arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/${local.genai_default_model_id}"

  genai_invocation_log_group = "/aws/bedrock/${local.name_prefix}-model-invocations"
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

# ------------------------------------------------------------------ API task role: Bedrock access
# Converse / ConverseStream are authorized as InvokeModel / InvokeModelWithResponseStream.
# The guardrail condition value is the guardrail ARN followed by ":<version>".
data "aws_iam_policy_document" "task_api_genai" {
  count = local.genai_count

  statement {
    sid       = "InvokeApprovedModelsWithGuardrail"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = concat(local.genai_model_arns, [for p in aws_bedrock_inference_profile.bu : p.arn])

    condition {
      test     = "StringEquals"
      variable = "bedrock:GuardrailIdentifier"
      values   = ["${module.guardrails[0].guardrail_arn}:${module.guardrails[0].guardrail_version}"]
    }
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [module.guardrails[0].guardrail_arn]
  }

  statement {
    sid       = "GuardrailKey"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.key_arns["genai"]]
  }
}

# bedrock-runtime endpoint: only this account's principals, only the approved models, this account's
# guardrails and application inference profiles.
data "aws_iam_policy_document" "bedrock_endpoint" {
  #checkov:skip=CKV_AWS_283:VPC endpoint policy; the principal is restricted to this account by aws:PrincipalAccount.
  count = local.genai_count

  statement {
    sid     = "ApprovedModelsFromThisAccount"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ApplyGuardrail"]
    resources = concat(local.genai_model_arns, [
      "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:guardrail/*",
      "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:application-inference-profile/*",
    ])

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }
}

# ------------------------------------------------------------------ Optional: application inference profile per BU
# Cost allocation per business unit (tags) on the default model; the API reads the profile ARN from
# SSM genai/inference_profile/<bu> and uses it as the model ID.
resource "aws_bedrock_inference_profile" "bu" {
  for_each = local.genai_bu_profiles

  name        = "${local.name_prefix}-genai-${each.key}"
  description = "MMM GenAI default model for business unit ${each.key}"

  model_source {
    copy_from = local.genai_default_model_source_arn
  }

  tags = merge(local.tags, { Component = "genai", BusinessUnit = each.key })
}

# ------------------------------------------------------------------ Optional: model invocation logging
# One setting per account and region. Metadata only unless Privacy approves text logging
# (bedrock_invocation_log_text = true).
resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  count = var.enable_genai && var.enable_bedrock_invocation_logging ? 1 : 0

  name              = local.genai_invocation_log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = module.kms.key_arns["logs"]

  tags = merge(local.tags, { Component = "genai" })
}

data "aws_iam_policy_document" "bedrock_logging_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:*"]
    }
  }
}

data "aws_iam_policy_document" "bedrock_logging" {
  statement {
    sid       = "WriteInvocationLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:${local.genai_invocation_log_group}:*"]
  }
}

resource "aws_iam_role" "bedrock_logging" {
  count = var.enable_genai && var.enable_bedrock_invocation_logging ? 1 : 0

  name                 = "${local.name_prefix}-bedrock-invocation-logging"
  assume_role_policy   = data.aws_iam_policy_document.bedrock_logging_trust.json
  permissions_boundary = module.permission_boundary.policy_arn

  tags = merge(local.tags, { Component = "genai" })
}

resource "aws_iam_role_policy" "bedrock_logging" {
  count = var.enable_genai && var.enable_bedrock_invocation_logging ? 1 : 0

  name   = "write-invocation-logs"
  role   = aws_iam_role.bedrock_logging[0].id
  policy = data.aws_iam_policy_document.bedrock_logging.json
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.enable_genai && var.enable_bedrock_invocation_logging ? 1 : 0

  logging_config {
    text_data_delivery_enabled      = var.bedrock_invocation_log_text
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = false
    video_data_delivery_enabled     = false

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations[0].name
      role_arn       = aws_iam_role.bedrock_logging[0].arn
    }
  }

  depends_on = [aws_iam_role_policy.bedrock_logging]
}

# ------------------------------------------------------------------ Bedrock alarms (default model)
resource "aws_cloudwatch_metric_alarm" "bedrock_invocation_errors" {
  count = local.genai_count

  alarm_name          = "${local.name_prefix}-bedrock-invocation-errors"
  alarm_description   = "Bedrock ${local.genai_default_model_id}: more than ${var.bedrock_error_alarm_threshold} client + server errors in 5 min - check model access, quotas and the guardrail (runbooks/genai.md)"
  evaluation_periods  = 1
  threshold           = var.bedrock_error_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.monitoring.alert_topic_arn]
  ok_actions          = [module.monitoring.alert_topic_arn]

  metric_query {
    id          = "errors"
    expression  = "client + server"
    label       = "Bedrock invocation errors"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = { client = "InvocationClientErrors", server = "InvocationServerErrors" }
    content {
      id = metric_query.key
      metric {
        namespace   = "AWS/Bedrock"
        metric_name = metric_query.value
        dimensions  = { ModelId = local.genai_default_model_id }
        stat        = "Sum"
        period      = 300
      }
    }
  }

  tags = merge(local.tags, { Component = "genai" })
}

resource "aws_cloudwatch_metric_alarm" "bedrock_throttles" {
  count = local.genai_count

  alarm_name          = "${local.name_prefix}-bedrock-throttles"
  alarm_description   = "Bedrock ${local.genai_default_model_id}: throttled for 15 min - raise the Bedrock tokens / requests per minute quota or check the token quotas (runbooks/genai.md)"
  namespace           = "AWS/Bedrock"
  metric_name         = "InvocationThrottles"
  dimensions          = { ModelId = local.genai_default_model_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.monitoring.alert_topic_arn]
  ok_actions          = [module.monitoring.alert_topic_arn]

  tags = merge(local.tags, { Component = "genai" })
}

resource "aws_cloudwatch_metric_alarm" "bedrock_latency_p95" {
  count = local.genai_count

  alarm_name          = "${local.name_prefix}-bedrock-latency-p95"
  alarm_description   = "Bedrock ${local.genai_default_model_id}: p95 latency above ${var.bedrock_latency_p95_ms} ms for 15 min (runbooks/genai.md)"
  namespace           = "AWS/Bedrock"
  metric_name         = "InvocationLatency"
  dimensions          = { ModelId = local.genai_default_model_id }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.bedrock_latency_p95_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.monitoring.alert_topic_arn]
  ok_actions          = [module.monitoring.alert_topic_arn]

  tags = merge(local.tags, { Component = "genai" })
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

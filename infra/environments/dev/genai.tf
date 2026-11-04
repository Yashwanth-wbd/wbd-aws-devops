# ================================================================== Step 14 - Release 2 GenAI (Bedrock)
# Everything here exists only with enable_genai = true. The API reaches the gateway through
# Service Connect (http://genai-gateway:8080); the gateway reaches Bedrock only through PrivateLink
# and passes the guardrail on every call. The user-facing switch is the genai_enabled SSM flag.
locals {
  genai_count        = var.enable_genai ? 1 : 0
  genai_service_name = "genai-gateway"
  genai_gateway_url  = "http://${local.genai_service_name}:${local.app_port}"
  genai_param_path   = "/mmm/${local.env_short}/genai"

  # Built from the name, so the endpoint policy does not depend on the service module.
  genai_task_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/${local.name_prefix}-task-genai"

  genai_sizing = {
    dev     = { min = 1, max = 2 }
    staging = { min = 1, max = 3 }
    prod    = { min = 2, max = 6 }
  }[var.environment]

  # Service Connect's Envoy proxy is managed through ecs-agent; the gateway has no internet route.
  genai_interface_endpoints = var.enable_genai ? ["ecs-agent"] : []
}

# ------------------------------------------------------------------ KMS (purpose genai)
# Bedrock writes invocation logs with this key; CloudWatch Logs is added by logs_service_purposes.
data "aws_iam_policy_document" "genai_key_bedrock" {
  statement {
    sid       = "AllowBedrockInvocationLogging"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# ------------------------------------------------------------------ Bedrock: endpoint, guardrail, logging, alarms, budget
module "bedrock" {
  source = "../../modules/bedrock"
  count  = local.genai_count

  name_prefix              = local.name_prefix
  environment              = var.environment
  approved_model_ids       = var.genai_approved_model_ids
  kms_key_arn              = module.kms.key_arns["genai"]
  permissions_boundary_arn = module.permission_boundary.policy_arn

  vpc_id                     = module.network.vpc_id
  endpoint_subnet_ids        = module.network.private_endpoint_subnet_ids
  endpoint_security_group_id = module.network.security_group_ids["endpoints"]
  invoker_role_arns          = [local.genai_task_role_arn]

  guardrail_version_label = var.genai_guardrail_version_label
  grounding_threshold     = var.genai_grounding_threshold
  relevance_threshold     = var.genai_relevance_threshold

  enable_invocation_logging  = var.enable_bedrock_invocation_logging
  invocation_log_bucket_name = "wbd-mmm-${local.env_short}-genai-logs-${local.region_code}"
  access_log_bucket          = module.log_bucket.bucket_name
  access_log_prefix          = "${module.log_bucket.prefixes.s3_access}/"
  log_retention_days         = var.log_retention_days

  alert_topic_arn        = module.monitoring.alert_topic_arn
  ecs_cluster_name       = module.ecs_cluster.cluster_name
  gateway_service_name   = "${local.name_prefix}-${local.genai_service_name}"
  gateway_log_group_name = "/ecs/${local.name_prefix}/${local.genai_service_name}"
  token_quotas           = var.genai_token_quotas

  monthly_budget_usd   = var.genai_monthly_budget_usd
  budget_alert_emails  = var.budget_alert_emails
  budget_service_names = var.genai_budget_service_names

  tags = local.tags
}

# ------------------------------------------------------------------ Runtime settings (SSM)
# Token quotas (genai/token_quota/<bu>) and the genai_enabled flag live in module.secrets (Step 5).
resource "aws_ssm_parameter" "genai" {
  #checkov:skip=CKV2_AWS_34:Non-secret identifiers (model ID, guardrail ID and version); nothing sensitive.
  for_each = var.enable_genai ? {
    model_id          = { value = var.genai_approved_model_ids[0], description = "Bedrock model the gateway calls (one of the approved IDs)" }
    guardrail_id      = { value = module.bedrock[0].guardrail_id, description = "Guardrail passed on every call" }
    guardrail_version = { value = module.bedrock[0].guardrail_version, description = "Pinned guardrail version" }
  } : {}

  name        = "${local.genai_param_path}/${each.key}"
  description = each.value.description
  type        = "String"
  value       = each.value.value
  tier        = "Standard"

  tags = merge(local.tags, { Component = "genai", Name = "${local.genai_param_path}/${each.key}" })
}

# ------------------------------------------------------------------ Gateway task role
data "aws_iam_policy_document" "task_genai" {
  count = local.genai_count

  statement {
    sid       = "InvokeApprovedModels"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = module.bedrock[0].model_arns
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [module.bedrock[0].guardrail_arn]
  }

  statement {
    sid       = "GuardrailKey"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.key_arns["genai"]]
  }

  statement {
    sid       = "ReadGenAIConfig"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter${local.genai_param_path}", "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter${local.genai_param_path}/*"]
  }

  # Bedrock only through the PrivateLink endpoint (requests without aws:SourceVpce are denied too).
  statement {
    sid       = "DenyBedrockOutsidePrivateLink"
    effect    = "Deny"
    actions   = ["bedrock:*"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [module.bedrock[0].vpc_endpoint_id]
    }
  }

  # No training, fine-tuning, provisioned throughput, logging or guardrail changes from the app.
  statement {
    sid       = "DenyBedrockChanges"
    effect    = "Deny"
    actions   = ["bedrock:Create*", "bedrock:Update*", "bedrock:Delete*", "bedrock:Put*", "bedrock:Start*", "bedrock:Stop*"]
    resources = ["*"]
  }
}

# ------------------------------------------------------------------ Gateway service
# Internal only: no load balancer; reachable from API tasks on the app port (Service Connect).
module "svc_genai" {
  source = "../../modules/ecs-service"
  count  = local.genai_count

  name_prefix              = local.name_prefix
  service_name             = local.genai_service_name
  task_role_suffix         = "genai"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["genai"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_genai[0].json

  image          = var.seed_image
  command        = local.seed_api_command
  cpu            = 512
  memory         = 1024
  container_port = local.app_port
  environment = {
    APP_ENV           = var.environment
    AWS_REGION        = var.aws_region
    SSM_PREFIX        = "/mmm/${local.env_short}"
    GENAI_PARAM_PATH  = local.genai_param_path
    METRICS_NAMESPACE = "MMM/GenAI"
  }
  secrets = {
    GENAI_ENABLED           = module.secrets.parameter_arns["genai_enabled"]
    GENAI_MODEL_ID          = aws_ssm_parameter.genai["model_id"].arn
    GENAI_GUARDRAIL_ID      = aws_ssm_parameter.genai["guardrail_id"].arn
    GENAI_GUARDRAIL_VERSION = aws_ssm_parameter.genai["guardrail_version"].arn
  }
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  desired_count                 = local.genai_sizing.min
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  service_connect_server        = { discovery_name = local.genai_service_name, port = local.app_port }
  exec_audit_log_group_arn      = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn              = module.ecs_cluster.exec_kms_key_arn
  enable_application_signals    = var.enable_application_signals

  autoscaling = { type = "cpu", min = local.genai_sizing.min, max = local.genai_sizing.max, cpu_target = 60 }
}

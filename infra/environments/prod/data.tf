# ================================================================== Step 13 - Data-team platform
# MWAA orchestrates; Databricks transforms, checks data quality, trains and registers models
# (MLflow in Unity Catalog); the ECS workers only score with the "production" model.
# Everything in this file exists only when enable_data_platform = true.
locals {
  data_platform_kms_purposes = var.enable_data_platform ? concat(["mwaa"], [for bu in var.business_units : "s3-${bu}"]) : []
  bu_key_arns                = var.enable_data_platform ? { for bu in var.business_units : bu => module.kms.key_arns["s3-${bu}"] } : {}

  model_catalog = coalesce(var.databricks_catalog, "mmm_${local.env_short}")

  mwaa_sizing = {
    dev     = { class = "mw1.small", min = 1, max = 2 }
    staging = { class = "mw1.small", min = 1, max = 4 }
    prod    = { class = "mw1.medium", min = 2, max = 10 }
  }[var.environment]

  # Built from the name: the landing bucket policy can't reference the bucket module's own output.
  landing_bucket_arn = "arn:${local.partition}:s3:::wbd-mmm-${local.env_short}-landing-${local.region_code}"

  # Buckets MWAA tasks and Unity Catalog work on, and their keys.
  data_bucket_names = ["landing", "results", "data-quality"]
  data_key_arns     = concat([module.kms.key_arns["s3"]], values(local.bu_key_arns))
}

# Files under landing/<bu>/ must be encrypted with that business unit's key.
data "aws_iam_policy_document" "landing_bu_keys" {
  dynamic "statement" {
    for_each = local.bu_key_arns
    content {
      sid       = "RequireKeyOf${replace(title(statement.key), "-", "")}"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.landing_bucket_arn}/${statement.key}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [statement.value]
      }
    }
  }
}

# EventBridge writes undeliverable trigger events to the KMS-encrypted dead-letter queue.
data "aws_iam_policy_document" "sqs_key_eventbridge" {
  statement {
    sid       = "AllowEventBridgeDeadLetters"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

# ------------------------------------------------------------------ MWAA (20-30 min to create)
module "mwaa" {
  source = "../../modules/mwaa"
  count  = var.enable_data_platform ? 1 : 0

  name_prefix       = local.name_prefix
  environment_class = local.mwaa_sizing.class
  min_workers       = local.mwaa_sizing.min
  max_workers       = local.mwaa_sizing.max

  source_bucket_arn = module.buckets["mwaa"].bucket_arn
  subnet_ids        = module.network.private_app_subnet_ids
  security_group_id = module.network.security_group_ids["mwaa"]
  kms_key_arn       = module.kms.key_arns["mwaa"]

  secrets_prefix      = "mmm/${local.env_short}/airflow"
  secrets_kms_key_arn = module.kms.key_arns["secrets"]
  data_bucket_arns    = [for b in local.data_bucket_names : module.buckets[b].bucket_arn]
  data_kms_key_arns   = local.data_key_arns

  # Read by the DAGs as conf.get("mmm", "<key>")
  dag_settings = {
    environment    = var.environment
    name_prefix    = local.name_prefix
    landing_bucket = module.buckets["landing"].bucket_name
    results_bucket = module.buckets["results"].bucket_name
    quality_bucket = module.buckets["data-quality"].bucket_name
    business_units = join(",", var.business_units)
    model_catalog  = local.model_catalog
  }

  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Trigger: landing file / on-demand -> one DAG run
module "data_trigger" {
  source = "../../modules/data-trigger"
  count  = var.enable_data_platform ? 1 : 0

  name_prefix           = local.name_prefix
  environment           = var.environment
  landing_bucket_name   = module.buckets["landing"].bucket_name
  business_units        = var.business_units
  mwaa_environment_name = module.mwaa[0].environment_name
  airflow_role_arn      = module.mwaa[0].airflow_user_role_arn

  subnet_ids        = module.network.private_app_subnet_ids
  security_group_id = module.network.security_group_ids["data_trigger"]

  lambda_kms_key_arn = module.kms.key_arns["secrets"]
  sqs_kms_key_arn    = module.kms.key_arns["sqs"]
  logs_kms_key_arn   = module.kms.key_arns["logs"]
  log_retention_days = var.log_retention_days

  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Databricks: Unity Catalog role, PrivateLink, private DNS
module "databricks_access" {
  source = "../../modules/databricks-access"
  count  = var.enable_data_platform ? 1 : 0

  name_prefix           = local.name_prefix
  databricks_account_id = var.databricks_account_id
  self_assume_enabled   = var.databricks_self_assume_enabled

  bucket_arns  = [for b in local.data_bucket_names : module.buckets[b].bucket_arn]
  kms_key_arns = local.data_key_arns

  enable_privatelink         = var.enable_databricks_privatelink
  workspace_host             = var.databricks_host
  workspace_service_name     = var.databricks_privatelink_service_name
  vpc_id                     = module.network.vpc_id
  endpoint_subnet_ids        = module.network.private_endpoint_subnet_ids
  endpoint_security_group_id = module.network.security_group_ids["endpoints"]

  permissions_boundary_arn = module.permission_boundary.policy_arn
}

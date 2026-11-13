# ================================================================== Step 9 - Monitoring and logging
locals {
  # A CloudWatch alarm can only watch a certificate in its own region (the ALB certificate is regional).
  watched_certificates = { alb = var.alb_certificate_arn }

  state_machines = merge(
    { optimization = module.optimization_sfn.state_machine_arn },
    var.enable_data_platform ? { model-refresh = module.refresh_sfn[0].state_machine_arn, model-monitor = module.monitor_sfn[0].state_machine_arn } : {},
  )

  # Built from the name (as in the module), so monitoring does not wait for the export Lambda.
  databricks_export_function = var.enable_data_platform ? "${local.name_prefix}-databricks-export" : null

  lambda_functions = concat(
    [module.publisher.function_name, module.run_queue.dispatcher_function_name],
    var.enable_data_platform ? [local.databricks_export_function] : [],
    var.enable_genai ? [module.llm_gateway[0].proxy_function_name] : [],
  )

  # RDS for PostgreSQL max_connections = LEAST(DBInstanceClassMemory / 9531392, 5000); unknown class = no connections alarm
  rds_memory_gib = {
    "db.t4g.medium"  = 4
    "db.t4g.large"   = 8
    "db.m6g.large"   = 8
    "db.m6g.xlarge"  = 16
    "db.r6g.large"   = 16
    "db.r6g.xlarge"  = 32
    "db.r6g.2xlarge" = 64
    "db.r7g.large"   = 16
    "db.r7g.xlarge"  = 32
  }
  rds_max_connections = try(min(floor(local.rds_memory_gib[var.rds_instance_class] * 1073741824 / 9531392), 5000), null)

  # Shipped to Splunk: app logs, audit logs, WAF; VPC flow logs only on request (volume / licence).
  splunk_log_groups = merge(
    {
      api              = module.svc_api.log_group_name
      ui               = module.svc_ui.log_group_name
      migrate          = module.task_migrate.log_group_name
      ecs-exec         = module.ecs_cluster.exec_audit_log_group_name
      rds-postgres     = module.rds.log_group_name
      waf              = module.waf.log_group_name
      sfn-optimization = module.optimization_sfn.log_group_name
      publisher        = module.publisher.log_group_name
      run-dispatcher   = module.run_queue.log_group_name
      optimizer        = module.task_optimizer.log_group_name
    },
    var.ship_vpc_flow_logs ? { vpc-flow = module.network.flow_log_group_name } : {},
    var.enable_data_platform ? {
      sfn-model-refresh = module.refresh_sfn[0].log_group_name
      sfn-model-monitor = module.monitor_sfn[0].log_group_name
      sagemaker-jobs    = aws_cloudwatch_log_group.sagemaker["ProcessingJobs"].name
      sagemaker-train   = aws_cloudwatch_log_group.sagemaker["TrainingJobs"].name
      glue-jobs         = module.glue[0].log_group_name
      databricks-export = module.databricks_export[0].log_group_name
    } : {},
    var.enable_genai ? { for k, v in module.llm_gateway[0].log_group_names : "llm-${k}" => v } : {},
  )
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix  = local.name_prefix
  environment  = var.environment
  alert_emails = var.alert_emails

  alb_arn_suffix            = module.alb.alb_arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  rds_instance_id           = module.rds.instance_identifier
  ecs_cluster_name          = module.ecs_cluster.cluster_name
  ecs_service_names         = [module.svc_api.service_name, module.svc_ui.service_name]
  state_machine_arns        = local.state_machines
  lambda_function_names     = local.lambda_functions
  publisher_function_name   = module.publisher.function_name
  certificate_arns          = local.watched_certificates
  waf_web_acl_name          = module.waf.web_acl_name

  rds_max_connections  = local.rds_max_connections
  rds_free_storage_gib = max(floor(var.rds_allocated_storage / 10), 5)

  run_queue_name       = module.run_queue.queue_name
  run_dlq_name         = module.run_queue.dlq_name
  drift_business_units = var.enable_data_platform ? var.business_units : []

  # v4: optimizer task that fails to start, Glue job / Data Quality failures, export Lambda on the data-pipeline dashboard
  optimizer_task_family           = module.task_optimizer.task_definition_family
  glue_job_names                  = var.enable_data_platform ? values(module.glue[0].job_names) : []
  databricks_export_function_name = local.databricks_export_function
  data_business_units             = var.enable_data_platform ? var.business_units : []

  # Weekly schedule: alarm after 7 days without a successful refresh
  model_refresh_overdue_days = var.enable_data_platform && var.enable_model_refresh_schedule ? 7 : null

  llm_gateway_api_name = var.enable_genai ? module.llm_gateway[0].api_name : null
  genai_business_units = var.enable_genai ? keys(var.genai_token_quotas) : []

  enable_log_data_protection = var.enable_log_data_protection

  # Step 15: the BreakGlass permission set exists only in prod (docs/02 §6)
  enable_breakglass_alert = local.is_prod
}

# ------------------------------------------------------------------ Optional: S3 data events on the MMM data buckets
# Off by default: the WBD organization trail records them. On = own single-region trail into the
# log bucket (cloudtrail/), log files encrypted with the cloudtrail key and integrity-validated.
locals {
  data_events_trail_name = "${local.name_prefix}-data-events"
  data_events_trail_arn  = "arn:${local.partition}:cloudtrail:${var.aws_region}:${local.account_id}:trail/${local.data_events_trail_name}"
}

data "aws_iam_policy_document" "cloudtrail_key" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" means this key only and the trail ARN condition limits the use.
  #checkov:skip=CKV_AWS_111:Key policy; "*" means this key only and the trail ARN condition limits the use.
  #checkov:skip=CKV_AWS_356:Key policy; "*" means this key only and the trail ARN condition limits the use.
  statement {
    sid       = "AllowCloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.data_events_trail_arn]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }

  statement {
    sid       = "AllowCloudTrailDescribe"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.data_events_trail_arn]
    }
  }
}

resource "aws_cloudtrail" "data_events" {
  #checkov:skip=CKV_AWS_67:Data events of this region's buckets only; the WBD organization trail covers all regions.
  #checkov:skip=CKV_AWS_252:No SNS per log file; the files are read from S3 (Splunk / Athena).
  #checkov:skip=CKV2_AWS_10:No CloudWatch Logs copy; the WBD organization trail and Splunk do the alerting.
  count = var.enable_cloudtrail_data_events ? 1 : 0

  name                          = local.data_events_trail_name
  s3_bucket_name                = module.log_bucket.bucket_name
  s3_key_prefix                 = module.log_bucket.prefixes["cloudtrail"]
  kms_key_id                    = module.kms.key_arns["cloudtrail"]
  enable_log_file_validation    = true
  include_global_service_events = false
  is_multi_region_trail         = false

  advanced_event_selector {
    name = "S3 object events on the MMM data buckets"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = [for b in module.buckets : "${b.bucket_arn}/"]
    }

    dynamic "field_selector" {
      for_each = var.cloudtrail_data_events_include_reads ? [] : [1]
      content {
        field  = "readOnly"
        equals = ["false"]
      }
    }
  }

  tags = merge(local.tags, { Component = "audit" })

  depends_on = [module.log_bucket]
}

module "log_shipping" {
  source = "../../modules/log-shipping"

  name_prefix = local.name_prefix
  enabled     = var.enable_splunk_shipping

  hec_endpoint        = var.splunk_hec_endpoint
  hec_secret_arn      = module.secrets.secret_arns["splunk/hec"]
  secrets_kms_key_arn = module.kms.key_arns["secrets"]

  log_group_names = local.splunk_log_groups

  failed_records_bucket_arn = module.log_bucket.bucket_arn
  logs_kms_key_arn          = module.kms.key_arns["logs"]
  permissions_boundary_arn  = module.permission_boundary.policy_arn
  alert_topic_arn           = module.monitoring.alert_topic_arn
}

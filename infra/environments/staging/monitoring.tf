# ================================================================== Step 9 - Monitoring and logging
locals {
  # A CloudWatch alarm can only watch a certificate in its own region (the ALB certificate is regional).
  watched_certificates = { alb = var.alb_certificate_arn }

  state_machines = merge(
    { optimization = module.optimization_sfn.state_machine_arn },
    var.enable_data_platform ? { model-refresh = module.refresh_sfn[0].state_machine_arn } : {},
  )

  lambda_functions = concat([module.publisher.function_name], var.enable_genai ? [module.llm_gateway[0].proxy_function_name] : [])

  # Shipped to Splunk: app logs, audit logs, WAF; VPC flow logs only on request (volume / licence).
  splunk_log_groups = merge(
    {
      api              = module.svc_api.log_group_name
      ui               = module.svc_ui.log_group_name
      migrate          = module.task_migrate.log_group_name
      ecs-exec         = module.ecs_cluster.exec_audit_log_group_name
      aurora-postgres  = module.aurora.log_group_name
      waf              = module.waf.log_group_name
      sfn-optimization = module.optimization_sfn.log_group_name
      publisher        = module.publisher.log_group_name
      sagemaker-jobs   = aws_cloudwatch_log_group.sagemaker["ProcessingJobs"].name
    },
    var.ship_vpc_flow_logs ? { vpc-flow = module.network.flow_log_group_name } : {},
    var.enable_data_platform ? {
      sfn-model-refresh = module.refresh_sfn[0].log_group_name
      sagemaker-train   = aws_cloudwatch_log_group.sagemaker["TrainingJobs"].name
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
  aurora_cluster_id         = module.aurora.cluster_identifier
  ecs_cluster_name          = module.ecs_cluster.cluster_name
  ecs_service_names         = [module.svc_api.service_name, module.svc_ui.service_name]
  state_machine_arns        = local.state_machines
  lambda_function_names     = local.lambda_functions
  certificate_arns          = local.watched_certificates
  waf_web_acl_name          = module.waf.web_acl_name

  enable_log_data_protection = var.enable_log_data_protection

  # Step 15: the BreakGlass permission set exists only in prod (docs/02 §6)
  enable_breakglass_alert = local.is_prod
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

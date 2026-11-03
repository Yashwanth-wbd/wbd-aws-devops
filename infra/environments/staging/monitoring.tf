# ================================================================== Step 9 - Monitoring and logging
locals {
  redis_node_count = var.environment == "dev" ? 1 : 2
  # ElastiCache names its nodes <replication-group>-001, -002, ...
  redis_node_ids = [for i in range(local.redis_node_count) : format("%s-redis-%03d", local.name_prefix, i + 1)]

  # A CloudWatch alarm can only watch a certificate in its own region.
  watched_certificates = merge(
    { alb = var.alb_certificate_arn },
    var.aws_region == "us-east-1" ? { cloudfront = var.cloudfront_certificate_arn } : {},
  )

  # Shipped to Splunk: app logs, audit logs, WAF; VPC flow logs only on request (volume / licence).
  splunk_log_groups = merge(
    {
      api          = module.svc_api.log_group_name
      whatif       = module.svc_whatif.log_group_name
      optimizer    = module.svc_optimizer.log_group_name
      migrate      = module.task_migrate.log_group_name
      ecs-exec     = module.ecs_cluster.exec_audit_log_group_name
      rds-postgres = module.rds.log_group_names["postgresql"]
    },
    var.aws_region == "us-east-1" ? { waf = module.edge.waf_log_group_name } : {},
    var.ship_vpc_flow_logs ? { vpc-flow = module.network.flow_log_group_name } : {},
    var.enable_data_platform ? {
      data-trigger      = module.data_trigger[0].log_group_name
      airflow-task      = module.mwaa[0].log_group_names.task
      airflow-scheduler = module.mwaa[0].log_group_names.scheduler
    } : {},
  )
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix  = local.name_prefix
  environment  = var.environment
  alert_emails = var.alert_emails

  alb_arn_suffix              = module.alb.alb_arn_suffix
  api_target_group_arn_suffix = module.alb.target_group_arn_suffix
  queue_name                  = module.sqs.queue_name
  dlq_name                    = module.sqs.dlq_name
  rds_instance_id             = module.rds.db_instance_identifier
  redis_node_ids              = local.redis_node_ids
  ecs_cluster_name            = module.ecs_cluster.cluster_name
  ecs_service_names           = [module.svc_api.service_name, module.svc_whatif.service_name, module.svc_optimizer.service_name]
  certificate_arns            = local.watched_certificates
  waf_web_acl_name            = "${local.name_prefix}-cdn"
  cloudfront_distribution_id  = module.edge.distribution_id

  rds_free_storage_gib       = var.environment == "dev" ? 5 : 20
  enable_log_data_protection = var.enable_log_data_protection
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

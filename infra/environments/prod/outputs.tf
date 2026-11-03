# ------------------------------------------------------------------ Step 3 - Foundation
output "kms_key_arns" {
  description = "KMS key ARN per purpose."
  value       = module.kms.key_arns
}

output "permission_boundary_arn" {
  description = "Permission boundary attached to every Terraform-created role."
  value       = module.permission_boundary.policy_arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = module.iam_oidc.oidc_provider_arn
}

output "gha_role_arns" {
  description = "Pipeline role ARNs."
  value       = module.iam_oidc.role_arns
}

output "gha_trusted_subjects" {
  description = "GitHub OIDC subjects each pipeline role trusts."
  value       = module.iam_oidc.trusted_subjects
}

# ------------------------------------------------------------------ Step 4 - Network
output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs per tier."
  value = {
    public   = module.network.public_subnet_ids
    app      = module.network.private_app_subnet_ids
    data     = module.network.private_data_subnet_ids
    endpoint = module.network.private_endpoint_subnet_ids
  }
}

output "security_group_ids" {
  description = "Security group ID per role."
  value       = module.network.security_group_ids
}

output "nat_public_ips" {
  description = "NAT egress IPs."
  value       = module.network.nat_public_ips
}

output "flow_log_group_name" {
  description = "VPC flow log group."
  value       = module.network.flow_log_group_name
}

# ------------------------------------------------------------------ Step 5 - Secrets and configuration
output "secret_names" {
  description = "Secrets Manager names (values are never output)."
  value       = module.secrets.secret_names
}

output "parameter_names" {
  description = "SSM parameter names."
  value       = module.secrets.parameter_names
}

# ------------------------------------------------------------------ Step 6 - Platform
output "ecr_repository_urls" {
  description = "ECR repository URLs."
  value       = module.ecr.repository_urls
}

output "bucket_names" {
  description = "S3 bucket names (data, frontend and logs)."
  value       = merge({ for k, b in module.buckets : k => b.bucket_name }, { logs = module.log_bucket.bucket_name })
}

output "rds" {
  description = "Database endpoints and secrets (no passwords)."
  value = {
    proxy_endpoint         = module.rds.proxy_endpoint
    proxy_resource_id      = module.rds.proxy_resource_id
    instance_identifier    = module.rds.db_instance_identifier
    db_name                = module.rds.db_name
    master_user_secret_arn = module.rds.master_user_secret_arn
  }
}

output "redis_primary_endpoint" {
  description = "ElastiCache primary endpoint (TLS)."
  value       = module.elasticache.primary_endpoint
}

output "sqs" {
  description = "Job queue and DLQ."
  value = {
    queue_url = module.sqs.queue_url
    dlq_url   = module.sqs.dlq_url
  }
}

# ------------------------------------------------------------------ Step 7 - ECS
output "ecs" {
  description = "Cluster, services, task families and task roles."
  value = {
    cluster  = module.ecs_cluster.cluster_name
    services = [module.svc_api.service_name, module.svc_whatif.service_name, module.svc_optimizer.service_name]
    task_roles = {
      api       = module.svc_api.task_role_arn
      whatif    = module.svc_whatif.task_role_arn
      optimizer = module.svc_optimizer.task_role_arn
      migrate   = module.task_migrate.task_role_arn
    }
    migrate_task_family = module.task_migrate.task_definition_family
  }
}

output "alb_dns_name" {
  description = "ALB DNS name - point the origin hostname of alb_certificate_arn here (CNAME); CloudFront uses it in Step 8."
  value       = module.alb.alb_dns_name
}

output "platform_check_run_command" {
  description = "Runs the platform-check task (DevOps profile); then read its log group."
  value = var.enable_platform_check_task ? join(" ", [
    "aws ecs run-task --cluster ${module.ecs_cluster.cluster_name}",
    "--task-definition ${module.task_platform_check[0].task_definition_family}",
    "--launch-type FARGATE",
    "--network-configuration \"awsvpcConfiguration={subnets=[${join(",", module.network.private_app_subnet_ids)}],securityGroups=[${module.network.security_group_ids["workers"]},${module.network.security_group_ids["data_clients"]}],assignPublicIp=DISABLED}\"",
  ]) : null
}

# On-demand tasks get their security groups from run-task; bootstrap adds "workers" for NAT (public image, PyPI).
output "db_bootstrap_run_command" {
  description = "Runs the one-time DB bootstrap (only while enable_db_bootstrap = true)."
  value = var.enable_db_bootstrap ? join(" ", [
    "aws ecs run-task --cluster ${module.ecs_cluster.cluster_name}",
    "--task-definition ${module.task_migrate.task_definition_family}",
    "--launch-type FARGATE",
    "--network-configuration \"awsvpcConfiguration={subnets=[${join(",", module.network.private_app_subnet_ids)}],securityGroups=[${module.network.security_group_ids["workers"]},${module.network.security_group_ids["data_clients"]}],assignPublicIp=DISABLED}\"",
  ]) : null
}

# ------------------------------------------------------------------ Step 8 - Edge
output "edge" {
  description = "CloudFront, WAF and frontend release pointer."
  value = {
    app_url                  = module.edge.app_url
    distribution_id          = module.edge.distribution_id
    distribution_domain_name = module.edge.distribution_domain_name
    web_acl_arn              = module.edge.web_acl_arn
    waf_log_group            = module.edge.waf_log_group_name
    frontend_kvs_arn         = module.edge.frontend_kvs_arn
  }
}

output "dns_records_for_wbd" {
  description = "CNAME records WBD DNS must create (Route 53 is out of scope for now)."
  value = merge(
    { for a in var.cloudfront_aliases : a => module.edge.distribution_domain_name },
    { (var.alb_origin_domain_name) = module.alb.alb_dns_name },
  )
}

output "okta_app_settings" {
  description = "Values WBD enters in the Okta app of this environment (docs/04)."
  value = {
    sign_in_redirect_uri  = "${module.edge.app_url}/login/callback"
    sign_out_redirect_uri = module.edge.app_url
    trusted_origin_cors   = module.edge.app_url
    grant_type            = "Authorization Code with PKCE (no client secret)"
  }
}

# ------------------------------------------------------------------ Step 9 - Monitoring and logging
output "monitoring" {
  description = "Alert topic, alarms, event rules, dashboard and Splunk shipping."
  value = {
    alert_topic_arn     = module.monitoring.alert_topic_arn
    dashboard           = module.monitoring.dashboard_name
    alarms              = module.monitoring.alarm_names
    event_rules         = module.monitoring.event_rule_names
    splunk_stream       = module.log_shipping.delivery_stream_name
    splunk_log_groups   = module.log_shipping.shipped_log_groups
    splunk_ready_groups = keys(local.splunk_log_groups)
  }
}

# ------------------------------------------------------------------ GitHub Environment variables
output "github_environment_variables" {
  description = "Values to set as GitHub Environment variables for this environment (gh variable set ... --env <env>)."
  value = merge(
    {
      AWS_REGION                 = var.aws_region
      TF_PLAN_ROLE_ARN           = module.iam_oidc.role_arns["plan"]
      TF_APPLY_ROLE_ARN          = module.iam_oidc.role_arns["apply"]
      AWS_DEPLOY_ROLE_ARN        = module.iam_oidc.role_arns["deploy"]
      ECR_PUSH_ROLE_ARN          = module.iam_oidc.role_arns["ecr_push"]
      APP_SUBNET_IDS             = join(",", module.network.private_app_subnet_ids)
      DATA_CLIENTS_SG_ID         = module.network.security_group_ids["data_clients"]
      ECR_REGISTRY               = module.ecr.registry
      FRONTEND_BUCKET            = module.buckets["frontend"].bucket_name
      ECS_CLUSTER                = module.ecs_cluster.cluster_name
      APP_URL                    = module.edge.app_url
      CLOUDFRONT_DISTRIBUTION_ID = module.edge.distribution_id
      FRONTEND_KVS_ARN           = module.edge.frontend_kvs_arn
    },
    # Step 13: data.yml
    var.enable_data_platform ? {
      MWAA_BUCKET      = module.buckets["mwaa"].bucket_name
      MWAA_ENVIRONMENT = module.mwaa[0].environment_name
      QUALITY_BUCKET   = module.buckets["data-quality"].bucket_name
    } : {},
  )
}

# PR plans, the nightly drift check and model governance run without a GitHub Environment
# (or in <env>-model-promotion), so they read repository variables.
output "github_repository_variables" {
  description = "Repository-level GitHub variables for this environment (gh variable set ... without --env)."
  value = merge(
    {
      AWS_REGION                                   = var.aws_region
      "TF_PLAN_ROLE_ARN_${upper(var.environment)}" = module.iam_oidc.role_arns["plan"]
    },
    var.enable_data_platform ? {
      "DATABRICKS_HOST_${upper(var.environment)}"              = var.databricks_host
      "DATABRICKS_EVAL_CLIENT_ID_${upper(var.environment)}"    = var.databricks_eval_client_id
      "DATABRICKS_PROMOTE_CLIENT_ID_${upper(var.environment)}" = var.databricks_promote_client_id
      "MODEL_CATALOG_${upper(var.environment)}"                = local.model_catalog
    } : {},
  )
}

# ------------------------------------------------------------------ Step 10 - Backup and DR
output "backup" {
  description = "AWS Backup vault, plan and role (selection: tag backup = true)."
  value = {
    vault_name      = module.backup.vault_name
    dr_vault_arn    = module.backup.dr_vault_arn
    plan_id         = module.backup.plan_id
    backup_role_arn = module.backup.backup_role_arn
    selection_tag   = "${module.backup.selection_tag}=true"
    backed_up       = concat(["rds:${module.rds.db_instance_identifier}"], [for b in local.backed_up_buckets : "s3:${module.buckets[b].bucket_name}"])
  }
}

# ------------------------------------------------------------------ Step 13 - Data-team platform
output "data_platform" {
  description = "MWAA, buckets, per-BU keys, trigger and Databricks values (null while enable_data_platform = false)."
  value = var.enable_data_platform ? {
    mwaa_environment      = module.mwaa[0].environment_name
    airflow_ui            = module.mwaa[0].webserver_url
    mwaa_execution_role   = module.mwaa[0].execution_role_arn
    mwaa_bucket           = module.buckets["mwaa"].bucket_name
    landing_bucket        = module.buckets["landing"].bucket_name
    quality_bucket        = module.buckets["data-quality"].bucket_name
    business_unit_keys    = local.bu_key_arns
    trigger_function      = module.data_trigger[0].function_name
    trigger_log_group     = module.data_trigger[0].log_group_name
    trigger_dlq_url       = module.data_trigger[0].dlq_url
    uc_role_arn           = module.databricks_access[0].uc_role_arn
    uc_external_id        = module.databricks_access[0].uc_external_id
    workspace_endpoint_id = module.databricks_access[0].workspace_endpoint_id
    model_catalog         = local.model_catalog
    airflow_connection    = module.secrets.secret_names["airflow/connections/databricks_default"]
  } : null
}

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
  description = "NAT egress IPs (give these to vendors / Okta admins who allow-list by IP)."
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
  description = "S3 bucket names (data and logs)."
  value       = merge({ for k, b in module.buckets : k => b.bucket_name }, { logs = module.log_bucket.bucket_name })
}

output "rds" {
  description = "Database endpoints and secrets (no passwords)."
  value = {
    instance_identifier    = module.rds.instance_identifier
    endpoint               = module.rds.endpoint
    proxy_endpoint         = module.rds.proxy_endpoint
    proxy_resource_id      = module.rds.proxy_resource_id
    db_name                = module.rds.db_name
    master_user_secret_arn = module.rds.master_user_secret_arn
  }
}

# ------------------------------------------------------------------ Step 7 - ECS and optimization
output "ecs" {
  description = "Cluster, services, task families and task roles."
  value = {
    cluster  = module.ecs_cluster.cluster_name
    services = [module.svc_api.service_name, module.svc_ui.service_name]
    task_roles = {
      api     = module.svc_api.task_role_arn
      ui      = module.svc_ui.task_role_arn
      migrate = module.task_migrate.task_role_arn
    }
    migrate_task_family = module.task_migrate.task_definition_family
  }
}

output "optimization" {
  description = "Optimization state machine, run queue, optimizer task (family, role, release pointer) and results publisher."
  value = {
    state_machine_arn     = module.optimization_sfn.state_machine_arn
    queue_url             = module.run_queue.queue_url
    dlq_arn               = module.run_queue.dlq_arn
    dispatcher            = module.run_queue.dispatcher_function_name
    max_runs_param        = module.secrets.parameter_names["optimization/max_concurrent_runs"]
    optimizer_task_family = module.task_optimizer.task_definition_family
    optimizer_task_role   = module.task_optimizer.task_role_arn
    optimizer_task_param  = aws_ssm_parameter.optimizer_task.name
    publisher             = module.publisher.function_name
    publisher_alias       = module.publisher.alias_arn
  }
}

output "platform_check_run_command" {
  description = "Runs the platform-check task (DevOps profile); then read its log group."
  value = var.enable_platform_check_task ? join(" ", [
    "aws ecs run-task --cluster ${module.ecs_cluster.cluster_name}",
    "--task-definition ${module.task_platform_check[0].task_definition_family}",
    "--launch-type FARGATE",
    "--network-configuration \"awsvpcConfiguration={subnets=[${join(",", module.network.private_app_subnet_ids)}],securityGroups=[${module.network.security_group_ids["tasks"]},${module.network.security_group_ids["data_clients"]}],assignPublicIp=DISABLED}\"",
  ]) : null
}

# On-demand tasks get their security groups from run-task; bootstrap adds "tasks" for NAT (public image, PyPI).
output "db_bootstrap_run_command" {
  description = "Runs the one-time DB bootstrap (only while enable_db_bootstrap = true)."
  value = var.enable_db_bootstrap ? join(" ", [
    "aws ecs run-task --cluster ${module.ecs_cluster.cluster_name}",
    "--task-definition ${module.task_migrate.task_definition_family}",
    "--launch-type FARGATE",
    "--network-configuration \"awsvpcConfiguration={subnets=[${join(",", module.network.private_app_subnet_ids)}],securityGroups=[${module.network.security_group_ids["tasks"]},${module.network.security_group_ids["data_clients"]}],assignPublicIp=DISABLED}\"",
  ]) : null
}

# ------------------------------------------------------------------ Step 8 - Front door and sign-in
output "front_door" {
  description = "App URL, ALB, WAF and Okta sign-in values."
  value = {
    app_url        = local.app_url
    alb_dns_name   = module.alb.alb_dns_name
    web_acl_arn    = module.waf.web_acl_arn
    waf_log_group  = module.waf.log_group_name
    okta_issuer    = local.okta_issuer
    okta_client_id = var.okta_client_id
    sign_in        = var.okta_sign_in_enabled ? "okta" : "closed (503 until okta_sign_in_enabled = true)"
    logout_url     = local.okta_logout_url
  }
}

output "dns_records_for_wbd" {
  description = "CNAME WBD DNS must create when Route 53 is not used (route53_zone_id = null)."
  value       = var.route53_zone_id == null ? { (var.app_domain_name) = module.alb.alb_dns_name } : {}
}

output "okta_app_settings" {
  description = "Values the WBD Identity team enters in the Okta OIDC app of this environment (docs/04)."
  value = {
    application_type         = "OIDC - Web Application"
    grant_types              = ["authorization_code"]
    sign_in_redirect_uris    = ["${local.app_url}/oauth2/idpresponse"]
    sign_out_redirect_uris   = ["${local.app_url}/"]
    initiate_login_uri       = "${local.app_url}/"
    scopes                   = ["openid", "profile", "email", "groups"]
    groups_claim             = { name = "groups", filter = "Starts with mmm-", in = "ID token and userinfo" }
    client_secret_goes_to    = module.secrets.secret_names["okta/alb-client"]
    client_secret_json_shape = "{\"client_secret\": \"...\"}"
  }
}

# ------------------------------------------------------------------ Step 9 - Monitoring and logging
output "monitoring" {
  description = "Alert topic, alarms, event rules, dashboards and Splunk shipping."
  value = {
    alert_topic_arn = module.monitoring.alert_topic_arn
    dashboard       = module.monitoring.dashboard_name
    dashboards      = module.monitoring.dashboard_names
    alarms = concat(
      module.monitoring.alarm_names, module.optimization_sfn.alarm_names, [module.publisher.alarm_name],
      module.run_queue.alarm_names,
      var.enable_data_platform ? concat(module.refresh_sfn[0].alarm_names, module.monitor_sfn[0].alarm_names, [module.databricks_export[0].alarm_name], [for a in aws_cloudwatch_metric_alarm.model_drift : a.alarm_name]) : [],
    )
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
      AWS_REGION                     = var.aws_region
      TF_PLAN_ROLE_ARN               = module.iam_oidc.role_arns["plan"]
      TF_APPLY_ROLE_ARN              = module.iam_oidc.role_arns["apply"]
      AWS_DEPLOY_ROLE_ARN            = module.iam_oidc.role_arns["deploy"]
      ECR_PUSH_ROLE_ARN              = module.iam_oidc.role_arns["ecr_push"]
      APP_SUBNET_IDS                 = join(",", module.network.private_app_subnet_ids)
      DATA_CLIENTS_SG_ID             = module.network.security_group_ids["data_clients"]
      ECR_REGISTRY                   = module.ecr.registry
      ECS_CLUSTER                    = module.ecs_cluster.cluster_name
      APP_URL                        = local.app_url
      DB_INSTANCE_ID                 = module.rds.instance_identifier
      PUBLISHER_FUNCTION             = module.publisher.function_name
      OPTIMIZATION_STATE_MACHINE_ARN = module.optimization_sfn.state_machine_arn
      OPTIMIZATION_QUEUE_URL         = module.run_queue.queue_url
      # smoke.sh checks the Okta redirect only once sign-in is on (before that the ALB answers 503)
      SMOKE_CHECK_LOGIN = tostring(var.okta_sign_in_enabled)
      # deploy.yml registers a new optimizer task revision and writes its ARN to the pointer
      OPTIMIZER_TASK_FAMILY = module.task_optimizer.task_definition_family
      OPTIMIZER_TASK_PARAM  = aws_ssm_parameter.optimizer_task.name
      # deploy.yml writes the SageMaker training image URI here (data platform)
      SAGEMAKER_IMAGE_PARAM_PREFIX = "/mmm/${local.env_short}/images"
    },
    local.is_prod ? {} : {
      # deploy.yml post-release dry run (scripts/dry-run-optimization.sh)
      UPLOADS_BUCKET        = module.buckets["uploads"].bucket_name
      RESULTS_BUCKET        = module.buckets["results"].bucket_name
      MODELS_BUCKET         = module.buckets["models"].bucket_name
      DRY_RUN_BUSINESS_UNIT = var.business_units[0]
    },
    var.enable_data_platform ? {
      MODEL_REFRESH_STATE_MACHINE_ARN = module.refresh_sfn[0].state_machine_arn
      # glue.yml uploads data/glue/jobs/*.py to s3://<bucket>/scripts/
      GLUE_ASSETS_BUCKET = module.buckets["glue-assets"].bucket_name
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
      "MODEL_EVAL_ROLE_ARN_${upper(var.environment)}"    = module.iam_oidc.role_arns["model_eval"]
      "MODEL_APPROVE_ROLE_ARN_${upper(var.environment)}" = module.iam_oidc.role_arns["model_approve"]
      "MODELS_BUCKET_${upper(var.environment)}"          = module.buckets["models"].bucket_name
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
    backed_up       = concat(["rds:${module.rds.instance_identifier}"], [for b in local.backed_up_buckets : "s3:${module.buckets[b].bucket_name}" if contains(keys(local.data_buckets), b)])
  }
}

# ------------------------------------------------------------------ Step 13 - Data-team platform and model refresh
output "data_platform" {
  description = "Buckets, per-BU keys, Databricks export, Glue, model refresh and registry values (null while enable_data_platform = false)."
  value = var.enable_data_platform ? {
    landing_bucket         = module.buckets["landing"].bucket_name
    raw_export_prefix      = local.raw_export_prefix
    lakehouse_bucket       = module.buckets["lakehouse"].bucket_name
    training_data_bucket   = module.buckets["training-data"].bucket_name
    glue_assets_bucket     = module.buckets["glue-assets"].bucket_name
    business_unit_keys     = local.bu_key_arns
    uc_role_arn            = module.databricks_access[0].uc_role_arn
    uc_external_id         = module.databricks_access[0].uc_external_id
    workspace_endpoint_id  = module.databricks_access[0].workspace_endpoint_id
    export_function        = module.databricks_export[0].function_name
    export_job_ids_param   = module.secrets.parameter_names["databricks/export_job_ids"]
    glue_role              = module.glue[0].role_arn
    glue_jobs              = module.glue[0].job_names
    glue_databases         = module.glue[0].database_names
    glue_dq_ruleset        = module.glue[0].ruleset_name
    refresh_state_machine  = module.refresh_sfn[0].state_machine_arn
    refresh_schedules      = [for s in aws_scheduler_schedule.refresh : s.name]
    refresh_event_rule     = aws_cloudwatch_event_rule.refresh_on_demand[0].name
    monitor_state_machine  = module.monitor_sfn[0].state_machine_arn
    monitor_schedules      = [for s in aws_scheduler_schedule.monitor : s.name]
    training_role          = module.sagemaker_training[0].role_arn
    model_package_groups   = module.sagemaker_training[0].model_package_group_names
    training_image_pointer = aws_ssm_parameter.sagemaker_image["training"].name
  } : null
}

# ------------------------------------------------------------------ Step 14 - Release 2 GenAI
output "genai" {
  description = "LLM gateway and guardrail values (null while enable_genai = false)."
  value = var.enable_genai ? {
    gateway_url       = module.llm_gateway[0].invoke_url
    rest_api_id       = module.llm_gateway[0].rest_api_id
    proxy_function    = module.llm_gateway[0].proxy_function_name
    log_groups        = module.llm_gateway[0].log_group_names
    alarms            = concat(module.llm_gateway[0].alarm_names, [module.guardrails[0].alarm_name], [for a in aws_cloudwatch_metric_alarm.genai_token_quota : a.alarm_name])
    guardrail_id      = module.guardrails[0].guardrail_id
    guardrail_version = module.guardrails[0].guardrail_version
    provider_secrets  = [for p in keys(var.llm_providers) : module.secrets.secret_names["llm/${p}"]]
  } : null
}

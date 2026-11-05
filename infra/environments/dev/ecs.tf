# ================================================================== Step 7 - ECS compute
# Two long-running services behind the ALB: ui (web app) and api (REST + interactive what-if on
# the approved response curves). Full optimization runs are not done in ECS: the API starts the
# optimization state machine (optimization.tf), which runs a SageMaker Processing job.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  app_port   = 8080
  ui_port    = 8080

  ecs_sizing = {
    dev     = { api_min = 1, api_max = 2, ui_min = 1, ui_max = 2 }
    staging = { api_min = 2, api_max = 4, ui_min = 2, ui_max = 3 }
    prod    = { api_min = 3, api_max = 10, ui_min = 2, ui_max = 6 }
  }[var.environment]

  # rds-db:connect resource for a DB user through RDS Proxy (IAM auth)
  proxy_dbuser_arn = "arn:${local.partition}:rds-db:${var.aws_region}:${local.account_id}:dbuser:${module.aurora.proxy_resource_id}"
  ssm_path_arn     = "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/mmm/${local.env_short}/*"

  # Built from the name, so modules that trust the API role do not depend on the service module.
  api_task_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/${local.name_prefix}-task-api"

  bucket_arns = { for k, b in module.buckets : k => b.bucket_arn }

  # Non-secret settings every service that uses the database gets (task-definition environment)
  common_env = {
    APP_ENV        = var.environment
    AWS_REGION     = var.aws_region
    DB_HOST        = module.aurora.proxy_endpoint
    DB_PORT        = "5432"
    DB_NAME        = module.aurora.db_name
    RESULTS_BUCKET = module.buckets["results"].bucket_name
    SSM_PREFIX     = "/mmm/${local.env_short}"
  }

  # Injected at task start by the execution role (ARNs only in the task definition)
  api_secrets = {
    GENAI_ENABLED        = module.secrets.parameter_arns["genai_enabled"]
    COGNITO_USER_POOL_ID = module.secrets.parameter_arns["cognito/user_pool_id"]
    COGNITO_CLIENT_ID    = module.secrets.parameter_arns["cognito/client_id"]
  }

  # Seed revisions: placeholders so Terraform can create the services before the first real
  # image exists. deploy.yml (Step 11) registers the real task definitions.
  seed_http_command = ["python", "-c", <<-EOT
    import http.server as s
    class H(s.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200); self.end_headers(); self.wfile.write(b"seed - waiting for first deploy")
    s.HTTPServer(("", ${local.app_port}), H).serve_forever()
  EOT
  ]
  seed_migrate_command = ["python", "-c", "print('seed migrate task - replaced by deploy.yml')"]
}

# ------------------------------------------------------------------ Cluster
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix              = local.name_prefix
  logs_kms_key_arn         = module.kms.key_arns["logs"]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  secrets_kms_key_arn      = module.kms.key_arns["secrets"]
  ecr_kms_key_arn          = module.kms.key_arns["ecr"]
  parameter_path_arn       = local.ssm_path_arn
}

# ------------------------------------------------------------------ Task role policies (least privilege per service)
data "aws_iam_policy_document" "task_api" {
  statement {
    sid       = "DbConnectAsAppUser"
    actions   = ["rds-db:connect"]
    resources = ["${local.proxy_dbuser_arn}/mmm_app"]
  }

  # What-if runs in the API on the approved response curves.
  statement {
    sid       = "ReadApprovedCurves"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["models"], "${local.bucket_arns["models"]}/curves/*"]
  }

  # Full optimization: start / watch / cancel a run; progress comes from the execution status.
  statement {
    sid       = "StartOptimization"
    actions   = ["states:StartExecution"]
    resources = [module.optimization_sfn.state_machine_arn]
  }

  statement {
    sid       = "WatchOptimization"
    actions   = ["states:DescribeExecution", "states:StopExecution", "states:GetExecutionHistory"]
    resources = ["arn:${local.partition}:states:${var.aws_region}:${local.account_id}:execution:${module.optimization_sfn.state_machine_name}:*"]
  }

  statement {
    sid       = "ReadResults"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["results"], "${local.bucket_arns["results"]}/*"]
  }

  statement {
    sid       = "WriteRunInputs"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arns["results"]}/runs/*/input/*"]
  }

  statement {
    sid       = "Exports"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["exports"], "${local.bucket_arns["exports"]}/*"]
  }

  statement {
    sid       = "ApprovedScenariosWriteOnce"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arns["approved-worm"]}/*"]
  }

  statement {
    sid    = "NoWormTampering"
    effect = "Deny"
    actions = [
      "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:PutObjectRetention",
      "s3:PutObjectLegalHold", "s3:BypassGovernanceRetention", "s3:PutBucketObjectLockConfiguration",
    ]
    resources = [local.bucket_arns["approved-worm"], "${local.bucket_arns["approved-worm"]}/*"]
  }

  statement {
    sid       = "BucketKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms.key_arns["s3"]]
  }

  statement {
    sid       = "ReadConfig"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.ssm_path_arn, "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/mmm/${local.env_short}"]
  }

  # Step 14: the LLM gateway is a private API Gateway with IAM auth.
  dynamic "statement" {
    for_each = var.enable_genai ? [1] : []
    content {
      sid       = "InvokeLlmGateway"
      actions   = ["execute-api:Invoke"]
      resources = [module.llm_gateway[0].execution_arn]
    }
  }
}

# The UI container only serves static files; it calls no AWS API.
data "aws_iam_policy_document" "task_ui" {
  statement {
    sid       = "ReadOwnConfig"
    actions   = ["ssm:GetParameter"]
    resources = [module.secrets.parameter_arns["genai_enabled"]]
  }
}

data "aws_iam_policy_document" "task_migrate" {
  statement {
    sid       = "DbConnectAsMigrationUser"
    actions   = ["rds-db:connect"]
    resources = concat(["${local.proxy_dbuser_arn}/mmm_migrator"], var.enable_db_bootstrap ? ["${local.proxy_dbuser_arn}/mmm_admin"] : [])
  }

  # Bootstrap only: db-bootstrap.py writes the generated DB user passwords to their secrets.
  dynamic "statement" {
    for_each = var.enable_db_bootstrap ? [1] : []
    content {
      sid       = "BootstrapDbUserSecrets"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue"]
      resources = [module.secrets.secret_arns["rds/migrate"], module.secrets.secret_arns["rds/proxy"]]
    }
  }

  dynamic "statement" {
    for_each = var.enable_db_bootstrap ? [1] : []
    content {
      sid       = "BootstrapSecretsKey"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [module.kms.key_arns["secrets"]]
    }
  }
}

data "aws_iam_policy_document" "task_platform_check" {
  statement {
    sid       = "S3RoundTrip"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${local.bucket_arns["results"]}/platform-check/*"]
  }

  statement {
    sid       = "BucketKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms.key_arns["s3"]]
  }

  statement {
    sid       = "DescribeOptimization"
    actions   = ["states:DescribeStateMachine"]
    resources = [module.optimization_sfn.state_machine_arn]
  }

  statement {
    sid       = "ReadImagePointers"
    actions   = ["ssm:GetParameter"]
    resources = [for p in aws_ssm_parameter.sagemaker_image : p.arn]
  }
}

# ------------------------------------------------------------------ Services
module "svc_api" {
  source = "../../modules/ecs-service"

  name_prefix              = local.name_prefix
  service_name             = "api"
  task_role_suffix         = "api"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["api"], module.network.security_group_ids["data_clients"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_api.json

  image          = var.seed_image
  command        = local.seed_http_command
  cpu            = 1024
  memory         = 2048
  container_port = local.app_port
  environment = merge(local.common_env, {
    MODELS_BUCKET                  = module.buckets["models"].bucket_name
    EXPORTS_BUCKET                 = module.buckets["exports"].bucket_name
    APPROVED_BUCKET                = module.buckets["approved-worm"].bucket_name
    DB_USER                        = "mmm_app"
    OPTIMIZATION_STATE_MACHINE_ARN = module.optimization_sfn.state_machine_arn
    # The API verifies the x-amzn-oidc-data header: signer must be this ALB
    ALB_ARN = module.alb.alb_arn
  }, var.enable_genai ? { LLM_GATEWAY_URL = module.llm_gateway[0].invoke_url } : {})
  secrets            = local.api_secrets
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  desired_count              = local.ecs_sizing.api_min
  target_group_arn           = module.alb.target_group_arns["api"]
  exec_audit_log_group_arn   = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn           = module.ecs_cluster.exec_kms_key_arn
  enable_application_signals = var.enable_application_signals

  autoscaling = { type = "cpu", min = local.ecs_sizing.api_min, max = local.ecs_sizing.api_max, cpu_target = 60 }
}

module "svc_ui" {
  source = "../../modules/ecs-service"

  name_prefix              = local.name_prefix
  service_name             = "ui"
  task_role_suffix         = "ui"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["ui"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_ui.json

  image          = var.seed_image
  command        = local.seed_http_command
  cpu            = 256
  memory         = 512
  container_port = local.ui_port
  environment = {
    APP_ENV       = var.environment
    API_BASE_PATH = "/api"
    LOGOUT_URL    = module.cognito.logout_url
  }
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  desired_count            = local.ecs_sizing.ui_min
  target_group_arn         = module.alb.target_group_arns["ui"]
  exec_audit_log_group_arn = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn         = module.ecs_cluster.exec_kms_key_arn

  autoscaling = { type = "cpu", min = local.ecs_sizing.ui_min, max = local.ecs_sizing.ui_max, cpu_target = 60 }
}

# Migrate: task definition only; deploy.yml runs it as a one-off task before each deploy.
# With enable_db_bootstrap it runs scripts/db-bootstrap.py instead (first-time DB setup).
module "task_migrate" {
  source = "../../modules/ecs-service"

  name_prefix              = local.name_prefix
  service_name             = "migrate"
  task_role_suffix         = "migrate"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["data_clients"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_migrate.json

  image       = var.seed_image
  entry_point = var.enable_db_bootstrap ? ["python", "-c"] : null
  command     = var.enable_db_bootstrap ? [file("${path.module}/../../../scripts/db-bootstrap.py")] : local.seed_migrate_command
  cpu         = 256
  memory      = 512
  environment = merge(local.common_env, { DB_USER = "mmm_migrator" }, var.enable_db_bootstrap ? {
    DB_ADMIN_USER     = "mmm_admin"
    MIGRATE_SECRET_ID = module.secrets.secret_arns["rds/migrate"]
    APP_SECRET_ID     = module.secrets.secret_arns["rds/proxy"]
    HOME              = "/tmp"
  } : {})
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  create_service           = false
  exec_audit_log_group_arn = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn         = module.ecs_cluster.exec_kms_key_arn
}

# Platform check: one-off task that proves the network paths and IAM of Steps 4-8 (run by DevOps).
module "task_platform_check" {
  source = "../../modules/ecs-service"
  count  = var.enable_platform_check_task ? 1 : 0

  name_prefix              = local.name_prefix
  service_name             = "platform-check"
  task_role_suffix         = "platform-check"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["tasks"], module.network.security_group_ids["data_clients"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_platform_check.json

  image       = "public.ecr.aws/aws-cli/aws-cli:latest"
  user        = null
  entry_point = ["bash", "-c"]
  command     = [file("${path.module}/../../../scripts/platform-check.sh")]
  cpu         = 256
  memory      = 512
  environment = merge(local.common_env, {
    HOME                           = "/tmp"
    OPTIMIZATION_STATE_MACHINE_ARN = module.optimization_sfn.state_machine_arn
    IMAGE_PARAMETER_NAMES          = join(",", [for p in aws_ssm_parameter.sagemaker_image : p.name])
    APP_URL                        = local.app_url
  })

  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  create_service           = false
  enable_execute_command   = false
  exec_audit_log_group_arn = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn         = module.ecs_cluster.exec_kms_key_arn
}

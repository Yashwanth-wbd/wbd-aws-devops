# ================================================================== Step 7 - ECS compute
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  app_port   = 8080

  ecs_sizing = {
    dev     = { api_min = 1, api_max = 2, whatif_min = 1, whatif_max = 2, optimizer_max = 3 }
    staging = { api_min = 2, api_max = 4, whatif_min = 1, whatif_max = 4, optimizer_max = 5 }
    prod    = { api_min = 3, api_max = 10, whatif_min = 2, whatif_max = 6, optimizer_max = 10 }
  }[var.environment]

  # rds-db:connect resource for a DB user through RDS Proxy (IAM auth)
  proxy_dbuser_arn = "arn:${local.partition}:rds-db:${var.aws_region}:${local.account_id}:dbuser:${module.rds.proxy_resource_id}"
  ssm_path_arn     = "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/mmm/${local.env_short}/*"
  ecs_task_arns    = "arn:${local.partition}:ecs:${var.aws_region}:${local.account_id}:task/${local.name_prefix}-ecs/*"

  bucket_arns = { for k, b in module.buckets : k => b.bucket_arn }

  # Non-secret settings every service gets (task-definition environment)
  common_env = {
    APP_ENV            = var.environment
    AWS_REGION         = var.aws_region
    DB_HOST            = module.rds.proxy_endpoint
    DB_PORT            = "5432"
    DB_NAME            = module.rds.db_name
    REDIS_HOST         = module.elasticache.primary_endpoint
    REDIS_PORT         = "6379"
    OPTIMIZE_QUEUE_URL = module.sqs.queue_url
    RESULTS_BUCKET     = module.buckets["results"].bucket_name
    SSM_PREFIX         = "/mmm/${local.env_short}"
  }

  # Injected at task start by the execution role (ARNs only in the task definition)
  api_secrets = {
    REDIS_AUTH_TOKEN = module.secrets.secret_arns["redis/token"]
    GENAI_ENABLED    = module.secrets.parameter_arns["genai_enabled"]
    OKTA_ISSUER      = module.secrets.parameter_arns["okta/issuer"]
    OKTA_AUDIENCE    = module.secrets.parameter_arns["okta/audience"]
  }

  # Step 13: workers load the model version the "production" alias points to (MLflow, Unity Catalog).
  # Model name: <MODEL_CATALOG>.models.mmm_<business unit>. A promotion moves the alias; no redeploy.
  mlflow_env = {
    MLFLOW_TRACKING_URI = "databricks"
    MLFLOW_REGISTRY_URI = "databricks-uc"
    MODEL_CATALOG       = local.model_catalog
    MODEL_ALIAS         = "production"
  }

  # An empty secret makes the task fail to start, so the Databricks token is added only once it is filled.
  worker_secrets = merge(
    {
      REDIS_AUTH_TOKEN         = module.secrets.secret_arns["redis/token"]
      DATABRICKS_HOST          = module.secrets.parameter_arns["databricks/host"]
      DATABRICKS_SQL_HTTP_PATH = module.secrets.parameter_arns["databricks/sql_http_path"]
    },
    var.databricks_token_available ? { DATABRICKS_TOKEN = module.secrets.secret_arns["databricks/sp"] } : {},
  )

  # Seed revisions: placeholders so Terraform can create the services before the first real
  # image exists. deploy.yml (Step 11) registers the real task definitions.
  seed_api_command = ["python", "-c", <<-EOT
    import http.server as s
    class H(s.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200); self.end_headers(); self.wfile.write(b"seed - waiting for first deploy")
    s.HTTPServer(("", ${local.app_port}), H).serve_forever()
  EOT
  ]
  seed_worker_command  = ["python", "-c", "import time; print('seed worker - waiting for first deploy'); time.sleep(10**9)"]
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
  secret_arns = [
    module.secrets.secret_arns["redis/token"],
    module.secrets.secret_arns["databricks/sp"],
  ]
}

# ------------------------------------------------------------------ ALB
module "alb" {
  source = "../../modules/alb"

  name_prefix         = local.name_prefix
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  security_group_id   = module.network.security_group_ids["alb"]
  certificate_arn     = var.alb_certificate_arn
  origin_verify_value = module.secrets.generated_values["edge/origin-verify"]
  app_port            = local.app_port
  access_log_bucket   = module.log_bucket.bucket_name
  access_log_prefix   = module.log_bucket.prefixes.alb
  deletion_protection = local.is_prod
}

# ------------------------------------------------------------------ Task role policies (least privilege per service)
data "aws_iam_policy_document" "task_api" {
  statement {
    sid       = "DbConnectAsAppUser"
    actions   = ["rds-db:connect"]
    resources = ["${local.proxy_dbuser_arn}/mmm_app"]
  }

  statement {
    sid       = "SendJobs"
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [module.sqs.queue_arn]
  }

  statement {
    sid       = "QueueKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms.key_arns["sqs"]]
  }

  statement {
    sid       = "ReadResults"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["results"], "${local.bucket_arns["results"]}/*"]
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
}

data "aws_iam_policy_document" "task_worker" {
  statement {
    sid       = "DbConnectAsAppUser"
    actions   = ["rds-db:connect"]
    resources = ["${local.proxy_dbuser_arn}/mmm_app"]
  }

  statement {
    sid       = "ConsumeJobs"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = [module.sqs.queue_arn]
  }

  statement {
    sid       = "QueueKey"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.key_arns["sqs"]]
  }

  statement {
    sid       = "WriteResults"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["results"], "${local.bucket_arns["results"]}/*"]
  }

  statement {
    sid       = "BucketKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms.key_arns["s3"]]
  }

  # Worker marks itself protected while a job runs, so scale-in never stops a running job.
  statement {
    sid       = "TaskScaleInProtection"
    actions   = ["ecs:UpdateTaskProtection", "ecs:GetTaskProtection"]
    resources = [local.ecs_task_arns]
  }

  statement {
    sid       = "ReadConfig"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.ssm_path_arn, "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter/mmm/${local.env_short}"]
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
    sid       = "QueueRoundTrip"
    actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [module.sqs.queue_arn]
  }

  statement {
    sid       = "QueueKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms.key_arns["sqs"]]
  }

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
  command        = local.seed_api_command
  cpu            = 512
  memory         = 1024
  container_port = local.app_port
  environment = merge(local.common_env, {
    EXPORTS_BUCKET  = module.buckets["exports"].bucket_name
    APPROVED_BUCKET = module.buckets["approved-worm"].bucket_name
    DB_USER         = "mmm_app"
  }, var.enable_genai ? { GENAI_GATEWAY_URL = local.genai_gateway_url } : {})
  secrets            = local.api_secrets
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  desired_count                 = local.ecs_sizing.api_min
  target_group_arn              = module.alb.target_group_arn
  service_connect_namespace_arn = module.ecs_cluster.service_connect_namespace_arn
  exec_audit_log_group_arn      = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn              = module.ecs_cluster.exec_kms_key_arn
  enable_application_signals    = var.enable_application_signals

  autoscaling = { type = "cpu", min = local.ecs_sizing.api_min, max = local.ecs_sizing.api_max, cpu_target = 60 }
}

# What-if: always on (min 1-2) so interactive simulations answer in seconds.
module "svc_whatif" {
  source = "../../modules/ecs-service"

  name_prefix              = local.name_prefix
  service_name             = "whatif-worker"
  task_role_suffix         = "whatif"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["workers"], module.network.security_group_ids["data_clients"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_worker.json

  image              = var.seed_image
  command            = local.seed_worker_command
  cpu                = 1024
  memory             = 2048
  environment        = merge(local.common_env, local.mlflow_env, { JOB_TYPE = "whatif", DB_USER = "mmm_app" })
  secrets            = local.worker_secrets
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  desired_count              = local.ecs_sizing.whatif_min
  exec_audit_log_group_arn   = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn           = module.ecs_cluster.exec_kms_key_arn
  enable_application_signals = var.enable_application_signals

  autoscaling = { type = "sqs", min = local.ecs_sizing.whatif_min, max = local.ecs_sizing.whatif_max, queue_name = module.sqs.queue_name }
}

# Optimizer: scales 0 -> N on queue backlog, back to 0 when the queue is empty.
module "svc_optimizer" {
  source = "../../modules/ecs-service"

  name_prefix              = local.name_prefix
  service_name             = "optimizer-worker"
  task_role_suffix         = "optimizer"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["workers"], module.network.security_group_ids["data_clients"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_worker.json

  image              = var.seed_image
  command            = local.seed_worker_command
  cpu                = 2048
  memory             = 4096
  environment        = merge(local.common_env, local.mlflow_env, { JOB_TYPE = "optimize", DB_USER = "mmm_app" })
  secrets            = local.worker_secrets
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  desired_count              = 0
  exec_audit_log_group_arn   = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn           = module.ecs_cluster.exec_kms_key_arn
  enable_application_signals = var.enable_application_signals

  autoscaling = { type = "sqs", min = 0, max = local.ecs_sizing.optimizer_max, queue_name = module.sqs.queue_name }
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

# Platform check: one-off task that proves the network paths and IAM of Steps 4-7 (run by DevOps).
module "task_platform_check" {
  source = "../../modules/ecs-service"
  count  = var.enable_platform_check_task ? 1 : 0

  name_prefix              = local.name_prefix
  service_name             = "platform-check"
  task_role_suffix         = "platform-check"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["workers"], module.network.security_group_ids["data_clients"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_platform_check.json

  image       = "public.ecr.aws/aws-cli/aws-cli:latest"
  user        = null
  entry_point = ["bash", "-c"]
  command     = [file("${path.module}/../../../scripts/platform-check.sh")]
  cpu         = 256
  memory      = 512
  environment = merge(local.common_env, { HOME = "/tmp" })
  secrets     = { REDIS_AUTH_TOKEN = module.secrets.secret_arns["redis/token"] }

  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  create_service           = false
  enable_execute_command   = false
  exec_audit_log_group_arn = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn         = module.ecs_cluster.exec_kms_key_arn
}

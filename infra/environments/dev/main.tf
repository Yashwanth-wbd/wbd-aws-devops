locals {
  env_short = {
    dev     = "dev"
    staging = "stg"
    prod    = "prd"
  }[var.environment]

  name_prefix = "mmm-${local.env_short}"

  # us-east-1 -> use1; matches the bucket names created by infra/bootstrap
  region_parts = split("-", var.aws_region)
  region_code  = "${local.region_parts[0]}${substr(local.region_parts[1], 0, 1)}${local.region_parts[2]}"

  state_bucket_name = "wbd-mmm-${local.env_short}-tfstate-${local.region_code}"

  # Mandatory tags; modules add Component.
  tags = {
    Application        = "mmm-media-allocation"
    Environment        = local.env_short
    Owner              = var.owner
    CostCenter         = var.cost_center
    BusinessUnit       = "shared"
    DataClassification = var.data_classification
    ManagedBy          = "terraform"
    Component          = "platform"
  }

  # Environment-specific behaviour of the shared modules.
  is_prod = var.environment == "prod"
  next_environment = {
    dev     = ["staging"]
    staging = ["prod"]
    prod    = []
  }[var.environment]
}

# ================================================================== Step 3 - Foundation
module "kms" {
  source = "../../modules/kms"

  name_prefix = local.name_prefix

  # Step 13: MWAA key + one S3 key per business unit (data isolation); Step 14: GenAI key
  purposes              = concat(["rds", "s3", "logs", "secrets", "sqs", "ecr"], local.data_platform_kms_purposes, var.enable_genai ? ["genai"] : [])
  logs_service_purposes = concat(["logs"], var.enable_data_platform ? ["mwaa"] : [], var.enable_genai ? ["genai"] : [])

  # Step 8: CloudFront (OAC) decrypts frontend objects; Step 13: EventBridge dead letters; Step 14: Bedrock logging
  additional_policy_documents = merge(
    { s3 = data.aws_iam_policy_document.s3_key_cloudfront.json },
    var.enable_data_platform ? { sqs = data.aws_iam_policy_document.sqs_key_eventbridge.json } : {},
    var.enable_genai ? { genai = data.aws_iam_policy_document.genai_key_bedrock.json } : {},
  )
}

module "permission_boundary" {
  source = "../../modules/permission-boundary"

  name_prefix     = local.name_prefix
  allowed_regions = var.allowed_regions
}

module "iam_oidc" {
  source = "../../modules/iam-oidc"

  name_prefix                = local.name_prefix
  environment                = var.environment
  env_short                  = local.env_short
  github_org                 = var.github_org
  github_repo                = var.github_repo
  create_oidc_provider       = var.create_github_oidc_provider
  existing_oidc_provider_arn = var.existing_github_oidc_provider_arn
  permissions_boundary_arn   = module.permission_boundary.policy_arn

  plan_allow_pull_requests      = !local.is_prod
  ecr_push_allow_main_branch    = var.environment == "dev"
  ecr_read_trusted_environments = local.next_environment
  enable_data_deploy            = var.enable_data_platform

  state_bucket_name   = local.state_bucket_name
  state_kms_key_arn   = var.state_kms_key_arn
  secrets_kms_key_arn = module.kms.key_arns["secrets"]
  s3_kms_key_arn      = module.kms.key_arns["s3"]
  ecr_kms_key_arn     = module.kms.key_arns["ecr"]
}

module "budgets" {
  source = "../../modules/budgets"

  name_prefix              = local.name_prefix
  monthly_limit_usd        = var.monthly_budget_usd
  alert_emails             = var.budget_alert_emails
  enable_anomaly_detection = var.enable_cost_anomaly_detection
  anomaly_threshold_usd    = var.cost_anomaly_threshold_usd
}

# ================================================================== Step 4 - Network
module "network" {
  source = "../../modules/network"

  name_prefix           = local.name_prefix
  vpc_cidr              = var.vpc_cidr
  availability_zone_ids = var.availability_zone_ids

  # dev: one shared NAT; staging/prod: one NAT per AZ
  single_nat_gateway = var.environment == "dev"
  enable_nat_gateway = var.enable_nat_gateway

  flow_logs_retention_days = var.flow_logs_retention_days
  logs_kms_key_arn         = module.kms.key_arns["logs"]
  permissions_boundary_arn = module.permission_boundary.policy_arn

  enable_transit_gateway = var.enable_transit_gateway
  transit_gateway_id     = var.transit_gateway_id
  transit_gateway_routes = var.transit_gateway_routes

  enable_resolver_forwarding = var.enable_resolver_forwarding
  resolver_forward_domains   = var.resolver_forward_domains
  resolver_target_ips        = var.resolver_target_ips

  create_mwaa_security_group = var.enable_data_platform

  # Step 14: GenAI gateway security group and the endpoint its Service Connect proxy needs
  create_genai_security_group    = var.enable_genai
  additional_interface_endpoints = local.genai_interface_endpoints
}

# ================================================================== Step 5 - Secrets and configuration
locals {
  # Secret values never come from variables: generated ones are random_password, the rest are
  # filled out-of-band by DevOps (docs/05-secrets-and-config.md).
  secrets = merge(
    {
      "api/db"             = { description = "App DB connection {host, port, dbname, username, password} - filled after the first migration" }
      "rds/proxy"          = { description = "App DB user {username, password} for RDS Proxy (never the admin user)" }
      "rds/migrate"        = { description = "Migration DB user {username, password} for RDS Proxy (schema owner, used only by the migrate task)" }
      "redis/token"        = { description = "ElastiCache auth token", generate = true, length = 64 }
      "edge/origin-verify" = { description = "CloudFront -> ALB X-Origin-Verify header value", generate = true, length = 48 }
      "databricks/sp"      = { description = "Databricks service-principal token from WBD Databricks admins" }
      "splunk/hec"         = { description = "Splunk HEC token from the WBD Splunk team" }
    },
    { for v in var.third_party_vendors : "thirdparty/${v}" => { description = "${v} API credentials from WBD data owners" } },
    # Step 13: Airflow connection read by the MWAA Secrets Manager backend (JSON connection, filled by DevOps)
    var.enable_data_platform ? {
      "airflow/connections/databricks_default" = { description = "Airflow connection to Databricks {conn_type, host, login (SP application ID), password (SP OAuth secret)}" }
    } : {},
  )

  parameters = merge(
    {
      "genai_enabled"            = { value = tostring(var.genai_enabled), description = "GenAI feature flag (Release 2)" }
      "okta/issuer"              = { value = var.okta_issuer, description = "Okta authorization server issuer URL" }
      "okta/client_id"           = { value = var.okta_spa_client_id, description = "Okta SPA client ID (public, PKCE)" }
      "okta/audience"            = { value = var.okta_audience, description = "Expected access-token audience" }
      "databricks/host"          = { value = var.databricks_host, description = "Databricks workspace URL" }
      "databricks/sql_http_path" = { value = var.databricks_sql_http_path, description = "Databricks SQL warehouse HTTP path" }
    },
    { for bu, q in var.genai_token_quotas : "genai/token_quota/${bu}" => { value = tostring(q), description = "Daily GenAI token quota for BU ${bu}" } },
  )
}

module "secrets" {
  source = "../../modules/secrets"

  path_prefix             = "mmm/${local.env_short}"
  kms_key_arn             = module.kms.key_arns["secrets"]
  recovery_window_in_days = local.is_prod ? 30 : 7

  secrets                      = local.secrets
  generated_secret_rotation_id = var.generated_secret_rotation_id
  parameters                   = local.parameters
}

# ================================================================== Step 6 - Platform (data and storage)
# Images are built once in dev and copied to staging/prod ECR by the promotion job (Step 11).
module "ecr" {
  source = "../../modules/ecr"

  repositories    = var.ecr_repositories
  kms_key_arn     = module.kms.key_arns["ecr"]
  keep_sha_images = var.environment == "dev" ? 30 : 1
}

module "log_bucket" {
  source = "../../modules/log-bucket"

  bucket_name    = "wbd-mmm-${local.env_short}-logs-${local.region_code}"
  retention_days = var.log_bucket_retention_days
}

locals {
  # Purpose-specific settings; every bucket gets versioning, KMS, TLS-only policy and access logs.
  all_data_buckets = {
    landing = {
      glacier_transition_days = 365
      expiration_days         = null
      object_lock             = null
      enable_eventbridge      = true
      enabled                 = true
    }
    results = {
      glacier_transition_days = null
      expiration_days         = null
      object_lock             = null
      enable_eventbridge      = false
      enabled                 = true
    }
    approved-worm = {
      glacier_transition_days = null
      expiration_days         = null
      object_lock             = { mode = var.approved_worm_lock_mode, days = var.approved_worm_retention_days }
      enable_eventbridge      = false
      enabled                 = true
    }
    exports = {
      glacier_transition_days = null
      expiration_days         = 30
      object_lock             = null
      enable_eventbridge      = false
      enabled                 = true
    }
    frontend = {
      glacier_transition_days = null
      expiration_days         = null
      object_lock             = null
      enable_eventbridge      = false
      enabled                 = true
    }
    # Step 13: Great Expectations suites (suites/) and validation results (results/)
    data-quality = {
      glacier_transition_days = null
      expiration_days         = 400
      object_lock             = null
      enable_eventbridge      = false
      enabled                 = var.enable_data_platform
    }
    # Step 13: Airflow DAGs (dags/) and requirements.txt, published only by data.yml
    mwaa = {
      glacier_transition_days = null
      expiration_days         = null
      object_lock             = null
      enable_eventbridge      = false
      enabled                 = var.enable_data_platform
    }
  }
  data_buckets = { for k, v in local.all_data_buckets : k => v if v.enabled }

  bucket_extra_policies = merge(
    { frontend = data.aws_iam_policy_document.frontend_oac.json },
    var.enable_data_platform ? { landing = data.aws_iam_policy_document.landing_bu_keys.json } : {},
  )
}

module "buckets" {
  source   = "../../modules/s3-bucket"
  for_each = local.data_buckets

  bucket_name             = "wbd-mmm-${local.env_short}-${each.key}-${local.region_code}"
  kms_key_arn             = module.kms.key_arns["s3"]
  access_log_bucket       = module.log_bucket.bucket_name
  access_log_prefix       = "${module.log_bucket.prefixes.s3_access}/"
  object_lock             = each.value.object_lock
  glacier_transition_days = each.value.glacier_transition_days
  expiration_days         = each.value.expiration_days
  noncurrent_version_days = each.key == "frontend" ? 30 : 90
  enable_eventbridge      = each.value.enable_eventbridge
  component               = each.key == "frontend" ? "frontend" : "data"
  additional_policy_json  = lookup(local.bucket_extra_policies, each.key, "")
  additional_kms_key_arns = each.key == "landing" ? values(local.bu_key_arns) : []
  tags                    = contains(local.backed_up_buckets, each.key) ? { backup = "true" } : {}
}

module "rds" {
  source = "../../modules/rds"

  name_prefix             = local.name_prefix
  subnet_ids              = module.network.private_data_subnet_ids
  db_security_group_id    = module.network.security_group_ids["rds"]
  proxy_security_group_id = module.network.security_group_ids["rds_proxy"]

  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage

  # dev: single-AZ, 7-day PITR, can be deleted; staging 14 days; prod: Multi-AZ, 35 days, deletion protection
  multi_az              = var.environment != "dev"
  deletion_protection   = local.is_prod
  backup_retention_days = { dev = 7, staging = 14, prod = 35 }[var.environment]
  apply_immediately     = var.environment == "dev"

  kms_key_arn              = module.kms.key_arns["rds"]
  secrets_kms_key_arn      = module.kms.key_arns["secrets"]
  logs_kms_key_arn         = module.kms.key_arns["logs"]
  log_retention_days       = var.log_retention_days
  permissions_boundary_arn = module.permission_boundary.policy_arn

  proxy_user_secret_arns = [module.secrets.secret_arns["rds/proxy"], module.secrets.secret_arns["rds/migrate"]]

  # Step 10: selected by the AWS Backup plan
  instance_tags = { backup = "true" }
}

module "elasticache" {
  source = "../../modules/elasticache"

  name_prefix       = local.name_prefix
  subnet_ids        = module.network.private_data_subnet_ids
  security_group_id = module.network.security_group_ids["redis"]

  node_type               = var.redis_node_type
  num_cache_clusters      = local.redis_node_count
  snapshot_retention_days = local.is_prod ? 7 : 1
  apply_immediately       = var.environment == "dev"

  auth_token         = module.secrets.generated_values["redis/token"]
  kms_key_arn        = module.kms.key_arns["rds"]
  logs_kms_key_arn   = module.kms.key_arns["logs"]
  log_retention_days = var.log_retention_days
}

module "sqs" {
  source = "../../modules/sqs"

  name_prefix = local.name_prefix
  kms_key_arn = module.kms.key_arns["sqs"]
}

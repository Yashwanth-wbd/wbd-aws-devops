# Staging: same code as dev (scripts/sync-environments.ps1); only these values differ.
# Staging behaviour from var.environment: 14-day PITR, 3 AZs / 3 NATs.
# ------------------------------------------------------------------ Account and region
environment = "staging"

# add actual value
aws_account_id = "222222222222"

# add actual value
aws_region = "us-east-1"

# add actual value
allowed_regions = ["us-east-1", "us-west-2"]

# ------------------------------------------------------------------ Terraform state (bootstrap output state_kms_key_arn)
# add actual value
state_kms_key_arn = "arn:aws:kms:us-east-1:222222222222:key/00000000-0000-0000-0000-000000000000"

# ------------------------------------------------------------------ GitHub OIDC
github_org  = "Yashwanth-wbd"
github_repo = "wbd-aws-devops"

create_github_oidc_provider = true

# ------------------------------------------------------------------ Budgets
# add actual value
monthly_budget_usd = 6000

# add actual value
budget_alert_emails = ["mmm-alerts@example.com"]

enable_cost_anomaly_detection = true
cost_anomaly_threshold_usd    = 100

# ------------------------------------------------------------------ Network (3 AZs, one NAT per AZ)
# add actual value
vpc_cidr = "10.40.32.0/19"

# add actual value
availability_zone_ids = ["use1-az1", "use1-az2", "use1-az4"]

# add actual value
enable_nat_gateway = true

flow_logs_retention_days = 90

# WBD hub connectivity - off until WBD Network shares the details
enable_transit_gateway = false

# add actual value
transit_gateway_id = "tgw-00000000000000000"

# add actual value
transit_gateway_routes = ["10.0.0.0/8"]

enable_resolver_forwarding = false

# add actual value
resolver_forward_domains = ["wbd.internal"]

# add actual value
resolver_target_ips = ["10.0.0.2", "10.0.0.3"]

# ------------------------------------------------------------------ Secrets and configuration
# Secret VALUES are never set here - only names and non-secret settings.

# add actual value
third_party_vendors = ["adstra", "inscape"]

generated_secret_rotation_id = "initial"
genai_enabled                = false

# add actual value
databricks_host = "https://dbc-00000000-0000.cloud.databricks.com"

# add actual value
genai_token_quotas = {
  usnetworks = 1000000
  streaming  = 1000000
  theatrical = 1000000
}

# ------------------------------------------------------------------ Platform (Step 6)
log_retention_days        = 90
log_bucket_retention_days = 90

# add actual value
approved_worm_lock_mode = "GOVERNANCE"

# add actual value
approved_worm_retention_days = 2555

# add actual value
training_data_retention_days = 365

# RDS for PostgreSQL (staging: Multi-AZ, prod-like class)
rds_engine_version = "16.6"
# add actual value
rds_instance_class = "db.r6g.large"
# add actual value
rds_allocated_storage = 100
# add actual value
rds_max_allocated_storage = 500
rds_multi_az              = true

# ------------------------------------------------------------------ ECS and optimization (Step 7)
enable_application_signals = false
enable_db_bootstrap        = false
enable_platform_check_task = true

# add actual value
optimizer_instance_type       = "ml.m5.xlarge"
optimizer_max_runtime_seconds = 3600
# add actual value
max_concurrent_runs    = 20
max_queue_wait_minutes = 30

# ------------------------------------------------------------------ Front door and sign-in (Step 8)
# add actual value
app_domain_name = "mmm-stg.example.wbd.com"
# add actual value
alb_certificate_arn = "arn:aws:acm:us-east-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"
# add actual value
alb_ingress_cidrs = ["0.0.0.0/0"]
route53_zone_id   = null
# add actual value
okta_issuer = "https://wbd.okta.com/oauth2/default"
# add actual value
okta_client_id = "0oa00000000000000001"
# true once mmm/staging/okta/alb-client holds {"client_secret":"..."}
okta_sign_in_enabled = false
session_hours        = 12
# add actual value
geo_allow_countries = []
waf_rate_limit      = 2000
waf_count_only      = []

# ------------------------------------------------------------------ Monitoring and Splunk (Step 9)
# add actual value
alert_emails               = ["mmm-devops-alerts@example.wbd.com"]
enable_log_data_protection = true
# Splunk: keep false until WBD gives the HEC endpoint and the token is stored in mmm/stg/splunk/hec
enable_splunk_shipping = false
# add actual value
splunk_hec_endpoint = "https://http-inputs-wbd.splunkcloud.com:443"
ship_vpc_flow_logs  = false

# ------------------------------------------------------------------ Backup and DR (Step 10)
# add actual value
dr_region = "us-west-2"
# staging: 14-day backups and the restore drills; no cross-region copy, no vault lock
enable_cross_region_copy = false
enable_vault_lock        = false

# ------------------------------------------------------------------ Data-team platform and model refresh (Step 13)
# Turn on after dev's data platform is validated
enable_data_platform = false
# Phase 2 of the Unity Catalog role: true after WBD registered the storage credential
databricks_self_assume_enabled = false
enable_databricks_privatelink  = false
# add actual value
databricks_account_id = "00000000-0000-0000-0000-000000000000"
# add actual value
databricks_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-00000000000000000"
# add actual value
databricks_sp_client_id = "00000000-0000-0000-0000-00000000c002"
# add actual value
databricks_refresh_job_id = 0
# add actual value
training_instance_type       = "ml.m5.2xlarge"
training_max_runtime_seconds = 14400
# add actual value
model_refresh_schedule        = "cron(0 6 ? * MON *)"
model_refresh_timezone        = "America/New_York"
enable_model_refresh_schedule = false
# add actual value
databricks_writeback_job_id = 0
# add actual value
model_monitor_schedule        = "cron(0 7 * * ? *)"
enable_model_monitor_schedule = false
# add actual value
model_drift_threshold = 0.2
auto_refresh_on_drift = false

# ------------------------------------------------------------------ Release 2 GenAI (Step 14)
# Turn on after the Release 1 gate (docs/11) and WBD approval of data egress to the providers
enable_genai = false
# add actual value
llm_providers = {
  openai    = { base_url = "https://api.openai.com", auth = "bearer" }
  anthropic = { base_url = "https://api.anthropic.com", auth = "x-api-key" }
  google    = { base_url = "https://generativelanguage.googleapis.com", auth = "x-goog-api-key" }
}
genai_reserved_concurrency        = 20
manage_apigw_account_logging_role = true
# add actual value
genai_grounding_threshold = 0.75
# add actual value
genai_relevance_threshold     = 0.75
genai_guardrail_version_label = "v1"

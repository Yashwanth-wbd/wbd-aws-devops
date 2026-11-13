# ------------------------------------------------------------------ Account and region
environment = "dev"

# add actual value
aws_account_id = "111111111111"

# add actual value
aws_region = "us-east-1"

# add actual value
allowed_regions = ["us-east-1", "us-west-2"]

# ------------------------------------------------------------------ Terraform state (bootstrap output state_kms_key_arn)
# add actual value
state_kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"

# ------------------------------------------------------------------ GitHub OIDC
github_org  = "Yashwanth-wbd"
github_repo = "wbd-aws-devops"

create_github_oidc_provider = true

# ------------------------------------------------------------------ Budgets
# add actual value
monthly_budget_usd = 3000

# add actual value
budget_alert_emails = ["mmm-alerts@example.com"]

enable_cost_anomaly_detection = true
cost_anomaly_threshold_usd    = 100

# ------------------------------------------------------------------ Network
# add actual value
vpc_cidr = "10.40.0.0/19"

# add actual value
availability_zone_ids = ["use1-az1", "use1-az2"]

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
log_retention_days        = 30
log_bucket_retention_days = 90

# add actual value
approved_worm_lock_mode = "GOVERNANCE"

# add actual value
approved_worm_retention_days = 2555

# add actual value
training_data_retention_days = 365

# RDS for PostgreSQL (dev: single-AZ, burstable, 7-day PITR)
rds_engine_version = "16.6"
# add actual value
rds_instance_class = "db.t4g.medium"
# add actual value
rds_allocated_storage = 50
# add actual value
rds_max_allocated_storage = 200
rds_multi_az              = false

# ------------------------------------------------------------------ ECS and optimization (Step 7)
enable_application_signals = false
enable_db_bootstrap        = false
enable_platform_check_task = true

# Optimizer task (ECS Fargate, one per run): 4 vCPU / 16 GB / 50 GiB scratch
# add actual value
optimizer_cpu                   = 4096
optimizer_memory                = 16384
optimizer_ephemeral_storage_gib = 50
optimizer_max_runtime_seconds   = 3600
# User uploads (presigned PUT from the browser)
# add actual value
uploads_retention_days = 90
# Run queue: runs allowed at the same time (SSM optimization/max_concurrent_runs) and queue wait limit
# add actual value
max_concurrent_runs    = 5
max_queue_wait_minutes = 30
# Results/data publisher Lambda (v5: also loads the Gold reference data into RDS; timeout up to 900 s)
# add actual value
publisher_timeout_seconds = 120
publisher_memory_mb       = 512

# ------------------------------------------------------------------ Front door and sign-in (Step 8)
# App host name; WBD DNS points it (CNAME) to terraform output front_door.alb_dns_name
# add actual value
app_domain_name = "mmm-dev.example.wbd.com"
# ACM certificate in aws_region for app_domain_name
# add actual value
alb_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
# Internet + WAF + Okta sign-in by default; set the WBD egress ranges to restrict further
# add actual value
alb_ingress_cidrs = ["0.0.0.0/0"]
# Route 53 zone in this account (null = WBD DNS adds the CNAME)
route53_zone_id = null
# WBD Okta OIDC app for dev (from the WBD Identity team; settings to give them: terraform output okta_app_settings)
# add actual value
okta_issuer = "https://wbd.okta.com/oauth2/default"
# add actual value
okta_client_id = "0oa00000000000000000"
# true once mmm/dev/okta/alb-client holds {"client_secret":"..."} - until then the ALB answers 503
okta_sign_in_enabled = false
session_hours        = 12
# add actual value
geo_allow_countries = []
waf_rate_limit      = 2000
waf_count_only      = []

# ------------------------------------------------------------------ Monitoring and Splunk (Step 9)
# On-call / DevOps distribution list for alarms
# add actual value
alert_emails = ["mmm-devops-alerts@example.wbd.com"]
# false if WBD already has an account-level CloudWatch Logs data protection policy
enable_log_data_protection = true
# Splunk: keep false until WBD gives the HEC endpoint and the token is stored in mmm/dev/splunk/hec
enable_splunk_shipping = false
# add actual value
splunk_hec_endpoint = "https://http-inputs-wbd.splunkcloud.com:443"
ship_vpc_flow_logs  = false
# v5: own S3 data-events trail on the data buckets, only if the WBD organization trail does not record them
# add actual value
enable_cloudtrail_data_events        = false
cloudtrail_data_events_include_reads = false

# ------------------------------------------------------------------ Backup and DR (Step 10)
# DR region approved by WBD (must also be in allowed_regions)
# add actual value
dr_region = "us-west-2"
# dev: no cross-region copy, no vault lock (prod sets both once WBD approves)
enable_cross_region_copy = false
enable_vault_lock        = false

# ------------------------------------------------------------------ Data-team platform and model refresh (Step 13)
# Turn on once WBD Databricks has shared the values below
enable_data_platform = false
# Phase 2 of the Unity Catalog role: true after WBD registered the storage credential
databricks_self_assume_enabled = false
# true once WBD gives the PrivateLink endpoint service name below
enable_databricks_privatelink = false
# add actual value
databricks_account_id = "00000000-0000-0000-0000-000000000000"
# add actual value
databricks_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-00000000000000000"
# WBD Databricks export job per business unit (the service principal is in mmm/dev/databricks/export-sp, docs/05)
# add actual value
databricks_export_job_ids = {
  usnetworks = 0
  streaming  = 0
  theatrical = 0
}
# Glue medallion and export jobs
glue_version = "5.0"
# add actual value
glue_worker_type         = "G.1X"
glue_number_of_workers   = 2
glue_job_timeout_minutes = 120
# false if WBD already manages the account's Glue Data Catalog encryption
manage_glue_catalog_encryption = true
# Gold reference-data exports (lakehouse rds-export/) are kept this long after the publisher loaded them
rds_export_retention_days = 30
# add actual value
training_instance_type       = "ml.m5.2xlarge"
training_max_runtime_seconds = 14400
# add actual value
evaluation_instance_type       = "ml.m5.xlarge"
evaluation_max_runtime_seconds = 3600
# add actual value
model_refresh_schedule        = "cron(0 6 ? * MON *)"
model_refresh_timezone        = "America/New_York"
enable_model_refresh_schedule = false
# Drift check per business unit (daily); auto refresh off = alarm only, a person decides
# add actual value
model_monitor_schedule        = "cron(0 7 * * ? *)"
enable_model_monitor_schedule = false
# add actual value
model_drift_threshold = 0.2
auto_refresh_on_drift = false

# ------------------------------------------------------------------ Release 2 GenAI (Step 14)
# Turn on after the Release 1 gate (docs/11) and WBD approval of data egress to the providers
enable_genai = false
# Approved providers; each gets the secret mmm/dev/llm/<name> ({"api_key": "..."}, filled by DevOps)
# add actual value
llm_providers = {
  openai    = { base_url = "https://api.openai.com", auth = "bearer" }
  anthropic = { base_url = "https://api.anthropic.com", auth = "x-api-key" }
  google    = { base_url = "https://generativelanguage.googleapis.com", auth = "x-goog-api-key" }
}
genai_reserved_concurrency = 20
# false if WBD already sets the account-level API Gateway CloudWatch role
manage_apigw_account_logging_role = true
# add actual value
genai_grounding_threshold = 0.75
# add actual value
genai_relevance_threshold     = 0.75
genai_guardrail_version_label = "v1"

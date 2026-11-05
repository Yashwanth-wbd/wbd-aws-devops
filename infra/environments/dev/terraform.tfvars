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

# Aurora Serverless v2 (dev: 0.5-4 ACU, writer only)
aurora_engine_version = "16.6"
# add actual value
aurora_min_acu = 0.5
# add actual value
aurora_max_acu = 4

# ------------------------------------------------------------------ ECS and optimization (Step 7)
enable_application_signals = false
enable_db_bootstrap        = false
enable_platform_check_task = true

# add actual value
optimizer_instance_type       = "ml.m5.xlarge"
optimizer_max_runtime_seconds = 3600

# ------------------------------------------------------------------ Front door and sign-in (Step 8)
# App host name; WBD DNS points it (CNAME) to terraform output front_door.alb_dns_name
# add actual value
app_domain_name = "mmm-dev.example.wbd.com"
# ACM certificate in aws_region for app_domain_name
# add actual value
alb_certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/00000000-0000-0000-0000-000000000000"
# Internet + WAF + Cognito by default; set the WBD egress ranges to restrict further
# add actual value
alb_ingress_cidrs = ["0.0.0.0/0"]
# Route 53 zone in this account (null = WBD DNS adds the CNAME)
route53_zone_id = null
# Metadata URL of the WBD Okta SAML app for dev (from the WBD Okta team)
# add actual value
okta_saml_metadata_url = "https://wbd.okta.com/app/exk00000000000000000/sso/saml/metadata"
# add actual value
cognito_domain_prefix = "wbd-mmm-dev"
session_hours         = 12
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
# Service principal used by the model-refresh state machine (its OAuth secret is set on the connection, docs/05)
# add actual value
databricks_sp_client_id = "00000000-0000-0000-0000-00000000c001"
# Lakeflow job that builds the training snapshot (databricks.yml output)
# add actual value
databricks_refresh_job_id = 0
# add actual value
training_instance_type       = "ml.m5.2xlarge"
training_max_runtime_seconds = 14400
# add actual value
model_refresh_schedule        = "cron(0 6 ? * MON *)"
model_refresh_timezone        = "America/New_York"
enable_model_refresh_schedule = false

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

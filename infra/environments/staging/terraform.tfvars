# Staging: same code as dev (scripts/sync-environments.ps1); only these values differ.
# ------------------------------------------------------------------ Account and region
environment = "staging"

# add actual value
aws_account_id = "222222222222"

# add actual value
aws_region = "us-east-1"

# add actual value
allowed_regions = ["us-east-1", "us-west-2"]

# ------------------------------------------------------------------ Tags
# add actual value
cost_center = "CC-000000"

# ------------------------------------------------------------------ Terraform state (bootstrap output state_kms_key_arn)
# add actual value
state_kms_key_arn = "arn:aws:kms:us-east-1:222222222222:key/00000000-0000-0000-0000-000000000000"

# ------------------------------------------------------------------ GitHub OIDC
# add actual value
github_org = "wbd-org"

# add actual value
github_repo = "wbd-mmm-platform"

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
okta_issuer = "https://wbd.okta.com/oauth2/aus0000000000000000"

# add actual value
okta_spa_client_id = "0oa00000000000000001"

# add actual value
okta_audience = "api://mmm-stg"

# add actual value
databricks_host = "https://dbc-00000000-0000.cloud.databricks.com"

# add actual value
databricks_sql_http_path = "/sql/1.0/warehouses/0000000000000001"

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
rds_instance_class    = "db.r6g.large"
rds_allocated_storage = 100

# add actual value
redis_node_type = "cache.r6g.large"

# ------------------------------------------------------------------ ECS (Step 7)
# ACM certificate for the ALB origin name, e.g. origin-mmm-stg.<wbd-domain>, issued in aws_region
# add actual value
alb_certificate_arn = "arn:aws:acm:us-east-1:222222222222:certificate/00000000-0000-0000-0000-000000000000"

enable_application_signals = false
databricks_token_available = false
enable_db_bootstrap        = false
enable_platform_check_task = true

# ------------------------------------------------------------------ Edge (Step 8)
# App domain name(s); WBD DNS points them (CNAME) to the CloudFront domain (terraform output edge)
# add actual value
cloudfront_aliases = ["mmm-stg.example.wbd.com"]
# ACM certificate in us-east-1 for the names above
# add actual value
cloudfront_certificate_arn = "arn:aws:acm:us-east-1:222222222222:certificate/11111111-1111-1111-1111-111111111111"
# Name on alb_certificate_arn, CNAME to terraform output alb_dns_name
# add actual value
alb_origin_domain_name = "origin-mmm-stg.example.wbd.com"
# add actual value
geo_allow_countries    = []
cloudfront_price_class = "PriceClass_100"
waf_rate_limit         = 2000

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

# ------------------------------------------------------------------ Data-team platform (Step 13)
# Turn on after dev's data platform is validated (MWAA takes 20-30 min to create)
enable_data_platform = false
# Phase 2 of the Unity Catalog role: true after WBD registered the storage credential
databricks_self_assume_enabled = false
enable_databricks_privatelink  = false
# add actual value
databricks_account_id = "00000000-0000-0000-0000-000000000000"
# add actual value
databricks_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-00000000000000000"
# add actual value
databricks_eval_client_id = "00000000-0000-0000-0000-00000000e002"
# add actual value
databricks_promote_client_id = "00000000-0000-0000-0000-00000000a002"

# ------------------------------------------------------------------ Account and region
variable "environment" {
  description = "Environment name (dev, staging or prod). Also the GitHub Environment name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "aws_account_id" {
  description = "AWS account ID for this environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "aws_region" {
  description = "WBD-approved primary region."
  type        = string
}

variable "allowed_regions" {
  description = "Regions the permission boundary allows: primary, us-east-1 (CloudFront/WAF/ACM) and the DR region if approved."
  type        = list(string)
}

# ------------------------------------------------------------------ Tags
variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "wbd-mmm-platform"
}

variable "cost_center" {
  description = "CostCenter tag value (WBD finance code)."
  type        = string
}

variable "data_classification" {
  description = "DataClassification tag value."
  type        = string
  default     = "confidential"
}

# ------------------------------------------------------------------ Terraform state (from infra/bootstrap)
variable "state_kms_key_arn" {
  description = "KMS key ARN of the state bucket (bootstrap output state_kms_key_arn)."
  type        = string
}

# ------------------------------------------------------------------ GitHub OIDC
variable "github_org" {
  description = "GitHub organisation."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider (false if the account already has one)."
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = "Existing provider ARN when create_github_oidc_provider = false."
  type        = string
  default     = null
}

# ------------------------------------------------------------------ Budgets
variable "monthly_budget_usd" {
  description = "Monthly cost budget for this account (USD)."
  type        = number
}

variable "budget_alert_emails" {
  description = "Recipients of budget and cost-anomaly alerts."
  type        = list(string)
}

variable "enable_cost_anomaly_detection" {
  description = "Create the Cost Anomaly Detection monitor (one per account allowed)."
  type        = bool
  default     = true
}

variable "cost_anomaly_threshold_usd" {
  description = "Minimum anomaly impact (USD) that triggers an email."
  type        = number
  default     = 100
}

# ------------------------------------------------------------------ Network
variable "vpc_cidr" {
  description = "VPC CIDR from WBD Network (/19, non-overlapping)."
  type        = string
}

variable "availability_zone_ids" {
  description = "AZ IDs for the subnets (2 in dev, 3 in staging/prod), e.g. use1-az1."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Use NAT gateways for internet egress (false if WBD provides central egress via the Transit Gateway)."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "VPC flow log retention in days."
  type        = number
  default     = 90
}

variable "enable_transit_gateway" {
  description = "Attach the VPC to the WBD Transit Gateway."
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "WBD Transit Gateway ID (shared via AWS RAM)."
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "WBD CIDRs routed from the private-app subnets to the Transit Gateway."
  type        = list(string)
  default     = []
}

variable "enable_resolver_forwarding" {
  description = "Forward WBD-internal DNS domains to the WBD DNS servers."
  type        = bool
  default     = false
}

variable "resolver_forward_domains" {
  description = "WBD-internal domains to forward."
  type        = list(string)
  default     = []
}

variable "resolver_target_ips" {
  description = "WBD DNS server IPs."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------ Secrets and configuration (no secret values here)
variable "third_party_vendors" {
  description = "Vendors that get a mmm/<env>/thirdparty/<vendor> secret container."
  type        = list(string)
  default     = []
}

variable "generated_secret_rotation_id" {
  description = "Change (e.g. to a date) to regenerate the Redis token and origin-verify value."
  type        = string
  default     = "initial"
}

variable "genai_enabled" {
  description = "Initial GenAI feature flag (Release 2)."
  type        = bool
  default     = false
}

variable "okta_issuer" {
  description = "Okta issuer URL (https://<org>.okta.com/oauth2/<auth-server-id>)."
  type        = string
}

variable "okta_spa_client_id" {
  description = "Okta SPA client ID for this environment (public value)."
  type        = string
}

variable "okta_audience" {
  description = "API audience in the Okta access token."
  type        = string
}

variable "databricks_host" {
  description = "Databricks workspace URL."
  type        = string
}

variable "databricks_sql_http_path" {
  description = "Databricks SQL warehouse HTTP path."
  type        = string
}

variable "genai_token_quotas" {
  description = "Daily GenAI token quota per business unit."
  type        = map(number)
  default     = {}
}

# ------------------------------------------------------------------ Platform (Step 6)
variable "ecr_repositories" {
  description = "ECR repositories in this account."
  type        = list(string)
  default     = ["mmm/api", "mmm/optimizer-worker", "mmm/genai-gateway"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention for service logs (RDS, ElastiCache; ECS from Step 7)."
  type        = number
  default     = 30
}

variable "log_bucket_retention_days" {
  description = "Days ALB / CloudFront / S3 access logs are kept in the log bucket."
  type        = number
  default     = 90
}

variable "approved_worm_lock_mode" {
  description = "Object Lock mode of the approved-worm bucket (GOVERNANCE in dev/staging, COMPLIANCE in prod)."
  type        = string
}

variable "approved_worm_retention_days" {
  description = "Object Lock default retention of approved scenarios."
  type        = number
}

variable "rds_instance_class" {
  description = "RDS PostgreSQL instance class."
  type        = string
}

variable "rds_allocated_storage" {
  description = "Initial RDS storage (GiB)."
  type        = number
  default     = 50
}

variable "rds_max_allocated_storage" {
  description = "RDS storage autoscaling ceiling (GiB)."
  type        = number
  default     = 200
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
}

# ------------------------------------------------------------------ ECS (Step 7)
variable "alb_certificate_arn" {
  description = "ACM certificate (this region) for the ALB origin hostname; CloudFront validates it."
  type        = string
}

variable "seed_image" {
  description = "Placeholder image of the Terraform-created task definitions until deploy.yml ships the real images."
  type        = string
  default     = "public.ecr.aws/docker/library/python:3.12-alpine"
}

variable "enable_application_signals" {
  description = "Add the CloudWatch agent sidecar + ADOT auto-instrumentation (Application Signals) to the services."
  type        = bool
  default     = false
}

variable "databricks_token_available" {
  description = "Set true once mmm/<env>/databricks/sp holds a value; then workers get DATABRICKS_TOKEN injected."
  type        = bool
  default     = false
}

variable "enable_db_bootstrap" {
  description = "First-time DB setup only: the migrate task runs scripts/db-bootstrap.py as the admin user through RDS Proxy. Set back to false afterwards."
  type        = bool
  default     = false
}

variable "enable_platform_check_task" {
  description = "Create the one-off platform-check task definition used to validate Steps 4-7."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------ Step 8 - Edge
variable "cloudfront_aliases" {
  description = "App domain names served by CloudFront (first one = APP_URL). WBD DNS adds CNAMEs to the distribution domain."
  type        = list(string)
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate in us-east-1 covering every name in cloudfront_aliases."
  type        = string
}

variable "alb_origin_domain_name" {
  description = "Origin host name on alb_certificate_arn (CNAME to alb_dns_name). CloudFront connects to the ALB with this name."
  type        = string
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100 = North America and Europe edges)."
  type        = string
  default     = "PriceClass_100"
}

variable "geo_allow_countries" {
  description = "Countries allowed to reach the app (ISO codes). Empty = no geo restriction."
  type        = list(string)
  default     = []
}

variable "waf_rate_limit" {
  description = "WAF: requests per 5 minutes per IP before blocking."
  type        = number
  default     = 2000
}

# ------------------------------------------------------------------ Step 9 - Monitoring and logging
variable "alert_emails" {
  description = "On-call / DevOps addresses that receive alarm emails (each confirms the subscription)."
  type        = list(string)
  default     = []
}

variable "enable_log_data_protection" {
  description = "Account-level CloudWatch Logs data protection policy (one per account; false if WBD already has one)."
  type        = bool
  default     = true
}

variable "enable_splunk_shipping" {
  description = "Ship logs to Splunk through Firehose. Turn on once splunk_hec_endpoint is real and mmm/<env>/splunk/hec holds {\"hec_token\":\"...\"}."
  type        = bool
  default     = false
}

variable "splunk_hec_endpoint" {
  description = "Splunk HEC URL reachable from the Firehose IP ranges of aws_region."
  type        = string
}

variable "ship_vpc_flow_logs" {
  description = "Also ship VPC flow logs to Splunk (high volume - agree the licence impact with WBD first)."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ Step 10 - Backup and DR
variable "dr_region" {
  description = "DR region for AWS Backup copies (must be in allowed_regions)."
  type        = string
  default     = "us-west-2"
}

variable "enable_cross_region_copy" {
  description = "Copy every recovery point to a vault in dr_region (prod, once WBD approves)."
  type        = bool
  default     = false
}

variable "enable_vault_lock" {
  description = "prod only: COMPLIANCE vault lock (irreversible after 3 days). Needs WBD approval."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ Step 13 - Data-team platform
variable "enable_data_platform" {
  description = "MWAA, data trigger, Databricks access, per-BU keys, data-quality and MWAA buckets. MWAA takes 20-30 min to create."
  type        = bool
  default     = false
}

variable "business_units" {
  description = "Business units: one S3 key each, landing prefixes <bu>/, one model each (lowercase, hyphens)."
  type        = list(string)
  default     = ["usnetworks", "streaming", "theatrical"]

  validation {
    condition     = alltrue([for bu in var.business_units : can(regex("^[a-z][a-z0-9-]*$", bu))])
    error_message = "business_units must be lowercase letters, digits and hyphens."
  }
}

variable "databricks_account_id" {
  description = "Databricks account ID (external ID of the Unity Catalog role)."
  type        = string
}

variable "databricks_self_assume_enabled" {
  description = "Phase 2 of the Unity Catalog role: true after WBD registered the storage credential."
  type        = bool
  default     = false
}

variable "enable_databricks_privatelink" {
  description = "Workspace PrivateLink endpoint + private DNS (needs databricks_privatelink_service_name)."
  type        = bool
  default     = false
}

variable "databricks_privatelink_service_name" {
  description = "Databricks workspace VPC endpoint service name for aws_region."
  type        = string
  default     = null
}

variable "databricks_catalog" {
  description = "Unity Catalog catalog of this environment (models: <catalog>.models.mmm_<bu>). null = mmm_<env_short>."
  type        = string
  default     = null
}

variable "databricks_eval_client_id" {
  description = "Databricks service principal (application ID) used by model-governance.yml to evaluate candidates (GitHub OIDC federation, no secret)."
  type        = string
}

variable "databricks_promote_client_id" {
  description = "Databricks service principal that may move the production alias; its federation policy trusts only the <env>-model-promotion GitHub Environment."
  type        = string
}

# ------------------------------------------------------------------ Step 14 - Release 2 GenAI (Bedrock)
variable "enable_genai" {
  description = "Create the Release 2 GenAI stack: Bedrock PrivateLink endpoint, guardrail, invocation logging, genai-gateway service, alarms and budget."
  type        = bool
  default     = false
}

variable "genai_approved_model_ids" {
  description = "Bedrock model IDs WBD approved; the first one is the gateway default (SSM genai/model_id). Nothing else can be invoked."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.genai_approved_model_ids : can(regex("^[a-z0-9][a-z0-9.:-]+$", id))])
    error_message = "genai_approved_model_ids must be Bedrock model IDs such as anthropic.claude-3-5-sonnet-20240620-v1:0."
  }
}

variable "genai_monthly_budget_usd" {
  description = "Monthly Bedrock cost budget (alerts at 50/80/100 % actual, 100 % forecast)."
  type        = number
  default     = 500
}

variable "genai_budget_service_names" {
  description = "Cost Explorer service names counted by the GenAI budget (Amazon Bedrock plus the Marketplace names of third-party models)."
  type        = list(string)
  default     = ["Amazon Bedrock"]
}

variable "genai_guardrail_version_label" {
  description = "Change (v1 -> v2) to publish a new guardrail version after a guardrail policy change."
  type        = string
  default     = "v1"
}

variable "genai_grounding_threshold" {
  description = "Contextual grounding threshold (0-0.99): answers not supported by the supplied MMM sources are blocked."
  type        = number
  default     = 0.75
}

variable "genai_relevance_threshold" {
  description = "Contextual relevance threshold (0-0.99): answers that do not address the question are blocked."
  type        = number
  default     = 0.75
}

variable "enable_bedrock_invocation_logging" {
  description = "Configure Bedrock model invocation logging in this account and region (false if WBD already manages it centrally)."
  type        = bool
  default     = true
}

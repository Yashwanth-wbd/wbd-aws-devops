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
  description = "Regions the permission boundary allows: the primary region and the DR region if approved."
  type        = list(string)
}

# ------------------------------------------------------------------ Tags
variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "wbd-mmm-platform"
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
  description = "GitHub organisation (or user) that owns the repository."
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
  description = "Change (e.g. to a date) to regenerate secrets the secrets module generates (none by default)."
  type        = string
  default     = "initial"
}

variable "genai_enabled" {
  description = "Initial GenAI feature flag (Release 2)."
  type        = bool
  default     = false
}

variable "databricks_host" {
  description = "Databricks workspace URL."
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
  default     = ["mmm/api", "mmm/ui", "mmm/optimizer", "mmm/sagemaker-training"]
}

variable "uploads_retention_days" {
  description = "Days user uploads (optimization / forecast inputs) are kept in the uploads bucket."
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "CloudWatch log retention for service logs (RDS, ECS, Lambda, Step Functions, SageMaker, WAF)."
  type        = number
  default     = 30
}

variable "log_bucket_retention_days" {
  description = "Days ALB / S3 access logs are kept in the log bucket."
  type        = number
  default     = 90
}

variable "approved_worm_lock_mode" {
  description = "Object Lock mode of the approved-worm and training-data buckets (GOVERNANCE in dev/staging, COMPLIANCE in prod)."
  type        = string
}

variable "approved_worm_retention_days" {
  description = "Object Lock default retention of approved scenarios."
  type        = number
}

variable "training_data_retention_days" {
  description = "Object Lock default retention of training snapshots (model reproducibility)."
  type        = number
  default     = 365
}

variable "rds_engine_version" {
  description = "RDS for PostgreSQL engine version."
  type        = string
  default     = "16.6"
}

variable "rds_instance_class" {
  description = "RDS instance class (db.t4g.medium dev, db.r6g.large staging, db.r6g.xlarge prod)."
  type        = string
}

variable "rds_allocated_storage" {
  description = "Initial gp3 storage in GiB."
  type        = number
}

variable "rds_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
}

variable "rds_multi_az" {
  description = "Multi-AZ standby (synchronous, automatic failover)."
  type        = bool
}

# ------------------------------------------------------------------ ECS and optimization (Step 7)
variable "seed_image" {
  description = "Placeholder image of the Terraform-created task definitions until deploy.yml ships the real images."
  type        = string
  default     = "public.ecr.aws/docker/library/python:3.12-alpine"
}

variable "enable_application_signals" {
  description = "Add the CloudWatch agent sidecar + ADOT auto-instrumentation (Application Signals) to the API service."
  type        = bool
  default     = false
}

variable "enable_db_bootstrap" {
  description = "First-time DB setup only: the migrate task runs scripts/db-bootstrap.py as the admin user through RDS Proxy. Set back to false afterwards."
  type        = bool
  default     = false
}

variable "enable_platform_check_task" {
  description = "Create the one-off platform-check task definition used to validate Steps 4-8."
  type        = bool
  default     = true
}

variable "optimizer_cpu" {
  description = "CPU units of one optimizer task (Fargate; 4096 = 4 vCPU)."
  type        = number
  default     = 4096
}

variable "optimizer_memory" {
  description = "Memory (MiB) of one optimizer task; must be valid for optimizer_cpu on Fargate."
  type        = number
  default     = 16384
}

variable "optimizer_ephemeral_storage_gib" {
  description = "Ephemeral storage (GiB, 21-200) of one optimizer task for input and solver files."
  type        = number
  default     = 50
}

variable "optimizer_max_runtime_seconds" {
  description = "Hard stop of one optimization run."
  type        = number
  default     = 3600
}

variable "max_concurrent_runs" {
  description = "Optimization runs allowed at the same time (SSM optimization/max_concurrent_runs, read by the run dispatcher on every batch, so a change applies within a minute without redeploying code). 0 pauses new runs."
  type        = number

  validation {
    condition     = var.max_concurrent_runs >= 0 && floor(var.max_concurrent_runs) == var.max_concurrent_runs
    error_message = "max_concurrent_runs must be a whole number >= 0."
  }
}

variable "max_queue_wait_minutes" {
  description = "A run request still waiting in the queue after this many minutes is dropped (metric ExpiredRunRequests) - the planner resubmits."
  type        = number
  default     = 30

  # A waiting request is received again every 6 minutes and moves to the DLQ after 10 receives (~60 min).
  validation {
    condition     = var.max_queue_wait_minutes >= 5 && var.max_queue_wait_minutes <= 50
    error_message = "max_queue_wait_minutes must be 5-50, so requests expire before the run queue moves them to the DLQ."
  }
}

# ------------------------------------------------------------------ Step 8 - Front door and sign-in
variable "app_domain_name" {
  description = "App host name (e.g. mmm-dev.<wbd-domain>); on alb_certificate_arn, CNAME / alias to the ALB."
  type        = string
}

variable "alb_certificate_arn" {
  description = "ACM certificate (this region) for app_domain_name."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "Source ranges allowed to reach the ALB: 0.0.0.0/0 (internet, filtered by the WAF and Okta sign-in) or the WBD egress ranges."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone of app_domain_name in this account. null = WBD DNS adds the CNAME (output dns_records_for_wbd)."
  type        = string
  default     = null
}

variable "okta_issuer" {
  description = "Issuer of the WBD Okta authorization server (https://<org>.okta.com or https://<org>.okta.com/oauth2/<server-id>)."
  type        = string

  validation {
    condition     = startswith(var.okta_issuer, "https://")
    error_message = "okta_issuer must be an https URL."
  }
}

variable "okta_client_id" {
  description = "Client ID of the WBD Okta OIDC app of this environment (not a secret; the client secret is in mmm/<env>/okta/alb-client)."
  type        = string
}

variable "okta_sign_in_enabled" {
  description = "Turn on Okta sign-in at the ALB. Set true once mmm/<env>/okta/alb-client holds {\"client_secret\":\"...\"}; until then the ALB answers 503."
  type        = bool
  default     = false
}

variable "session_hours" {
  description = "How long a planner stays signed in (ALB session cookie)."
  type        = number
  default     = 12
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

variable "waf_count_only" {
  description = "Common-rule-set rules switched to count (e.g. SizeRestrictions_BODY for large plan uploads)."
  type        = list(string)
  default     = []
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

# ------------------------------------------------------------------ Step 13 - Data-team platform and model refresh
variable "enable_data_platform" {
  description = "Per-BU keys, lakehouse / training-data / glue-assets buckets, Databricks export (Unity Catalog role + export Lambda), Glue medallion and export jobs, model-refresh and model-monitor state machines, schedules, SageMaker training and Model Registry."
  type        = bool
  default     = false
}

variable "business_units" {
  description = "Business units: one S3 key, landing prefix <bu>/, model package group and refresh schedule each (lowercase, hyphens)."
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

variable "databricks_export_job_ids" {
  description = "ID of the WBD Databricks export job per business unit (owned and deployed by WBD; SSM databricks/export_job_ids). The job writes raw Parquet to landing raw/databricks/<bu>/<refresh_id>/."
  type        = map(number)
  default     = {}
}

variable "glue_version" {
  description = "AWS Glue version of the medallion and export jobs (Spark 3.5 + Delta Lake in 5.0)."
  type        = string
  default     = "5.0"
}

variable "glue_worker_type" {
  description = "Glue worker type (G.1X = 4 vCPU / 16 GB, G.2X = 8 vCPU / 32 GB)."
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Workers per Glue job run (2 is the minimum)."
  type        = number
  default     = 2
}

variable "glue_job_timeout_minutes" {
  description = "Hard stop of one Glue job run."
  type        = number
  default     = 120
}

variable "manage_glue_catalog_encryption" {
  description = "Set the account's Glue Data Catalog encryption (one setting per account and region; false if WBD already manages it)."
  type        = bool
  default     = true
}

variable "evaluation_instance_type" {
  description = "SageMaker Processing instance of the model evaluation and drift check."
  type        = string
  default     = "ml.m5.xlarge"
}

variable "evaluation_max_runtime_seconds" {
  description = "Hard stop of one evaluation or drift-check job."
  type        = number
  default     = 3600
}

variable "training_instance_type" {
  description = "SageMaker training instance."
  type        = string
  default     = "ml.m5.2xlarge"
}

variable "training_max_runtime_seconds" {
  description = "Hard stop of one training job."
  type        = number
  default     = 4 * 3600
}

variable "model_refresh_schedule" {
  description = "EventBridge Scheduler expression of the scheduled refresh (one schedule per business unit)."
  type        = string
  default     = "cron(0 6 ? * MON *)"
}

variable "model_refresh_timezone" {
  description = "Time zone of model_refresh_schedule."
  type        = string
  default     = "America/New_York"
}

variable "enable_model_refresh_schedule" {
  description = "Schedules ENABLED (true) or DISABLED (false; on-demand refresh only)."
  type        = bool
  default     = false
}

variable "model_monitor_schedule" {
  description = "EventBridge Scheduler expression of the drift check (one schedule per business unit, model_refresh_timezone)."
  type        = string
  default     = "cron(0 7 * * ? *)"
}

variable "enable_model_monitor_schedule" {
  description = "Drift-check schedules ENABLED (true) or DISABLED (false; on-demand check only)."
  type        = bool
  default     = false
}

variable "model_drift_threshold" {
  description = "Default drift score (0-1) above which a business unit is flagged; per-BU overrides in data/model-thresholds.yaml (drift:)."
  type        = number
  default     = 0.2

  validation {
    condition     = var.model_drift_threshold > 0 && var.model_drift_threshold < 1
    error_message = "model_drift_threshold must be between 0 and 1."
  }
}

variable "auto_refresh_on_drift" {
  description = "When drift is detected, start a model refresh automatically (true) or only alarm (false; a person decides)."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ Step 14 - Release 2 GenAI (LLM gateway)
variable "enable_genai" {
  description = "Create the Release 2 GenAI stack: Bedrock guardrail, private API Gateway + proxy Lambda to the approved LLM providers, llm/<provider> secrets."
  type        = bool
  default     = false
}

variable "llm_providers" {
  description = "Approved external LLM providers: name => { base_url, auth = bearer | x-api-key | x-goog-api-key }. One secret llm/<name> each."
  type = map(object({
    base_url = string
    auth     = string
  }))
  default = {}
}

variable "genai_reserved_concurrency" {
  description = "Concurrency cap of the LLM proxy Lambda."
  type        = number
  default     = 20
}

variable "manage_apigw_account_logging_role" {
  description = "Set the account-level API Gateway CloudWatch role (false if WBD already manages it)."
  type        = bool
  default     = true
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

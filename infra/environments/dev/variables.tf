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

variable "app_repositories" {
  description = "WBD frontend, backend and data repositories (same GitHub organisation) whose pipelines release images, task revisions, Lambda code and Glue scripts through the deploy / ECR / model roles. Empty = only github_repo."
  type        = list(string)
  default     = []
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
  description = "Attach the VPC to the WBD Transit Gateway - the only path from the WBD network to the internal ALB (no public entry)."
  type        = bool
  default     = true
}

variable "transit_gateway_id" {
  description = "WBD Transit Gateway ID (shared via AWS RAM)."
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "WBD CIDRs routed from the private-app subnets to the Transit Gateway (include the alb_ingress_cidrs user ranges)."
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
  description = "CloudWatch log retention for service logs (RDS, ECS, Lambda, Step Functions, SageMaker, Glue, Bedrock invocations)."
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

variable "publisher_timeout_seconds" {
  description = "Timeout of the results/data publisher Lambda (optimization runs, Gold reference data, model results -> RDS). Raise it, up to 900, if reference-data loads grow."
  type        = number
  default     = 120

  validation {
    condition     = var.publisher_timeout_seconds >= 30 && var.publisher_timeout_seconds <= 900
    error_message = "publisher_timeout_seconds must be 30-900 (Lambda maximum)."
  }
}

variable "publisher_memory_mb" {
  description = "Memory of the results/data publisher Lambda (MiB; CPU scales with it)."
  type        = number
  default     = 512

  validation {
    condition     = var.publisher_memory_mb >= 128 && var.publisher_memory_mb <= 10240
    error_message = "publisher_memory_mb must be 128-10240."
  }
}

# ------------------------------------------------------------------ Step 8 - Private entry and sign-in
variable "app_domain_name" {
  description = "Internal app host name (e.g. mmm-dev.<wbd-internal-domain>) on alb_certificate_arn; WBD DNS (outside AWS) points it to the internal ALB (output dns_records_for_wbd)."
  type        = string
}

variable "alb_certificate_arn" {
  description = "ACM certificate (this region) for app_domain_name: DNS-validated, or from the WBD private CA (ACM Private CA / imported)."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "WBD ranges (corporate network / VPN, through the Transit Gateway) allowed to reach the internal ALB. 0.0.0.0/0 is rejected - no public entry."
  type        = list(string)

  validation {
    condition     = length(var.alb_ingress_cidrs) > 0 && !contains(var.alb_ingress_cidrs, "0.0.0.0/0")
    error_message = "alb_ingress_cidrs must be the WBD ranges; 0.0.0.0/0 is not allowed (internal application, no public entry)."
  }
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

variable "enable_cloudtrail_data_events" {
  description = "Own CloudTrail trail with S3 data events on the MMM data buckets (into the log bucket, cloudtrail/). false = the WBD organization trail already records them."
  type        = bool
  default     = false
}

variable "cloudtrail_data_events_include_reads" {
  description = "Also record S3 reads (GetObject) in the data-events trail; false = writes and deletes only (much lower cost)."
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

variable "rds_export_retention_days" {
  description = "Days the Gold reference-data exports (lakehouse rds-export/<bu>/<refresh_id>/) are kept after the publisher has loaded them into RDS."
  type        = number
  default     = 30
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

# ------------------------------------------------------------------ Step 14 - Release 2 GenAI (Amazon Bedrock)
variable "enable_genai" {
  description = "Create the Release 2 GenAI stack: Bedrock guardrail, bedrock-runtime VPC endpoint, API role access to the approved Bedrock models (guardrail enforced), SSM genai/*, Bedrock alarms and dashboard."
  type        = bool
  default     = false
}

variable "genai_model_ids" {
  description = "Bedrock model or inference-profile IDs the API may call. The first is the default and must be an Anthropic model; the others (OpenAI / Google on Bedrock) are optional, for experimentation (dev / staging, after approval)."
  type        = list(string)
  default     = ["us.anthropic.claude-sonnet-4-5-20250929-v1:0"]

  validation {
    condition     = length(var.genai_model_ids) > 0 && strcontains(var.genai_model_ids[0], "anthropic.")
    error_message = "genai_model_ids must start with the default Anthropic model (e.g. us.anthropic.claude-...)."
  }
}

variable "genai_inference_regions" {
  description = "Destination regions of the cross-region inference profile in genai_model_ids (us.* = us-east-1, us-east-2, us-west-2); the permission boundary allows only Bedrock InvokeModel there. The WBD SCP must allow them too."
  type        = list(string)
  default     = []
}

variable "enable_genai_bu_inference_profiles" {
  description = "Create one Bedrock application inference profile per business unit on the default model (cost allocation by BU tag; SSM genai/inference_profile/<bu>)."
  type        = bool
  default     = false
}

variable "enable_bedrock_invocation_logging" {
  description = "Bedrock model invocation logging to CloudWatch Logs (one setting per account and region; false if WBD already manages it)."
  type        = bool
  default     = false
}

variable "bedrock_invocation_log_text" {
  description = "Also log prompt and answer text in the invocation logs (only with WBD Privacy approval); false = metadata only."
  type        = bool
  default     = false
}

variable "bedrock_error_alarm_threshold" {
  description = "Bedrock client + server errors in 5 minutes above which bedrock-invocation-errors fires."
  type        = number
  default     = 5
}

variable "bedrock_latency_p95_ms" {
  description = "Bedrock p95 invocation latency (ms) above which bedrock-latency-p95 fires (3 x 5 minutes)."
  type        = number
  default     = 30000
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

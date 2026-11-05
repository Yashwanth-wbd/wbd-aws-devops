variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "environment" {
  description = "dev, staging or prod (dimension of the app metrics)."
  type        = string
}

variable "alert_emails" {
  description = "Email addresses subscribed to the alert topic (each must confirm the subscription email)."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------ What is monitored
variable "alb_arn_suffix" {
  description = "ALB ARN suffix (app/<name>/<id>)."
  type        = string
}

variable "target_group_arn_suffixes" {
  description = "Target group ARN suffix per service (alb module target_group_arn_suffixes; must contain api)."
  type        = map(string)

  validation {
    condition     = contains(keys(var.target_group_arn_suffixes), "api")
    error_message = "target_group_arn_suffixes must contain the api target group."
  }
}

variable "aurora_cluster_id" {
  description = "Aurora cluster identifier."
  type        = string
}

variable "aurora_max_connections" {
  description = "max_connections of the Aurora writer at max ACU (connections alarm). null = no connections alarm."
  type        = number
  default     = null
}

variable "aurora_has_reader" {
  description = "The cluster has a reader instance (replica lag alarm)."
  type        = bool
  default     = false
}

variable "state_machine_arns" {
  description = "Step Functions state machines (name => ARN). Keys optimization and model-refresh get their own dashboard and runtime / overdue alarms; failure and throttling alarms come from the step-functions module."
  type        = map(string)
  default     = {}
}

variable "lambda_function_names" {
  description = "Lambda functions shown on the dashboard. Each has its own errors alarm."
  type        = list(string)
  default     = []
}

variable "publisher_function_name" {
  description = "Results publisher Lambda (optimization dashboard)."
  type        = string
  default     = null
}

variable "llm_gateway_api_name" {
  description = "LLM gateway REST API name (GenAI dashboard). null = no GenAI dashboard."
  type        = string
  default     = null
}

variable "genai_business_units" {
  description = "Business units whose GenAI token use is shown on the GenAI dashboard."
  type        = list(string)
  default     = []
}

variable "ecs_cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "ecs_service_names" {
  description = "ECS services shown on the dashboard."
  type        = list(string)
}

variable "certificate_arns" {
  description = "ACM certificates in this stack's region to watch for expiry (name => ARN)."
  type        = map(string)
  default     = {}
}

variable "waf_web_acl_name" {
  description = "Regional WAF web ACL name on the ALB (dashboard)."
  type        = string
  default     = null
}

# ------------------------------------------------------------------ Thresholds
variable "api_5xx_percent_threshold" {
  description = "API 5xx rate (%) that raises the alarm."
  type        = number
  default     = 2
}

variable "api_5xx_min_requests" {
  description = "Below this many requests per minute the 5xx rate is not evaluated (avoids 1-of-2 = 50 %)."
  type        = number
  default     = 20
}

variable "aurora_cpu_percent" {
  description = "Aurora CPU threshold."
  type        = number
  default     = 80
}

variable "aurora_acu_percent" {
  description = "Aurora Serverless ACU utilization (% of max ACU) threshold."
  type        = number
  default     = 90
}

variable "aurora_connections_percent" {
  description = "Aurora connections threshold (% of aurora_max_connections)."
  type        = number
  default     = 80
}

variable "aurora_free_local_storage_gib" {
  description = "Alarm when the Aurora local (temporary) storage falls below this many GiB."
  type        = number
  default     = 2
}

variable "aurora_replica_lag_ms" {
  description = "Aurora reader replica lag threshold (ms)."
  type        = number
  default     = 1000
}

variable "availability_target_percent" {
  description = "Hourly availability (requests without a 5xx) below this raises the alarm."
  type        = number
  default     = 99.5
}

variable "availability_min_requests" {
  description = "Below this many requests per hour availability is not evaluated."
  type        = number
  default     = 100
}

variable "whatif_p95_ms" {
  description = "What-if p95 duration threshold (ms)."
  type        = number
  default     = 10000
}

variable "optimization_standard_p95_seconds" {
  description = "p95 duration (s) of standard optimization runs that raises the alarm (app metric OptimizeDurationMs, RunSize = standard)."
  type        = number
  default     = 120
}

variable "optimization_max_minutes" {
  description = "Any optimization execution (large runs included) longer than this raises the alarm."
  type        = number
  default     = 10
}

variable "model_refresh_overdue_days" {
  description = "Alarm when no model-refresh execution succeeded for this many days (1-7). null = off (scheduled refresh off)."
  type        = number
  default     = null

  validation {
    condition     = var.model_refresh_overdue_days == null || try(var.model_refresh_overdue_days >= 1 && var.model_refresh_overdue_days <= 7, false)
    error_message = "model_refresh_overdue_days must be 1-7 (CloudWatch evaluates at most 7 days)."
  }
}

variable "certificate_days_to_expiry" {
  description = "Alarm when a certificate expires in fewer days than this."
  type        = number
  default     = 30
}

# ------------------------------------------------------------------ App metric contract
variable "app_metric_namespace" {
  description = "CloudWatch namespace the services publish custom metrics to (Embedded Metric Format)."
  type        = string
  default     = "MMM"
}

# ------------------------------------------------------------------ Event alerts and logs
variable "enable_guardduty_alerts" {
  description = "Forward GuardDuty findings with severity >= 7 to the alert topic."
  type        = bool
  default     = true
}

variable "enable_breakglass_alert" {
  description = "Alert when the break-glass IAM Identity Center permission set signs in or makes a change (prod)."
  type        = bool
  default     = false
}

variable "breakglass_permission_set" {
  description = "Name of the break-glass permission set (role AWSReservedSSO_<name>_<suffix>)."
  type        = string
  default     = "BreakGlass"
}

variable "enable_log_data_protection" {
  description = "Account-level CloudWatch Logs data protection policy (only one is allowed per account; turn off if WBD already has one)."
  type        = bool
  default     = true
}

variable "data_protection_identifiers" {
  description = "Managed data identifiers masked in all log groups of the account."
  type        = list(string)
  default     = ["AwsSecretKey", "OpenSshPrivateKey", "PgpPrivateKey", "PkcsPrivateKey", "PuttyPrivateKey", "CreditCardNumber"]
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

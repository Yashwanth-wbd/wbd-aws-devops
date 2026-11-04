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

variable "api_target_group_arn_suffix" {
  description = "API target group ARN suffix (targetgroup/<name>/<id>)."
  type        = string
}

variable "queue_name" {
  description = "Job queue name."
  type        = string
}

variable "dlq_name" {
  description = "Dead-letter queue name."
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier."
  type        = string
}

variable "redis_node_ids" {
  description = "ElastiCache node IDs (<replication-group>-001, -002, ...)."
  type        = list(string)
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
  description = "CloudFront WAF web ACL name (dashboard; metrics are in us-east-1)."
  type        = string
  default     = null
}

variable "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (dashboard; metrics are in us-east-1)."
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

variable "queue_oldest_age_seconds" {
  description = "Oldest job waiting longer than this raises the alarm."
  type        = number
  default     = 300
}

variable "rds_cpu_percent" {
  description = "RDS CPU threshold."
  type        = number
  default     = 80
}

variable "rds_free_storage_gib" {
  description = "RDS free storage threshold (GiB)."
  type        = number
  default     = 10
}

variable "redis_percent" {
  description = "ElastiCache engine CPU and memory threshold."
  type        = number
  default     = 80
}

variable "whatif_p95_ms" {
  description = "What-if p95 duration threshold (ms)."
  type        = number
  default     = 10000
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

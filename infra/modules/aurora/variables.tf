# ------------------------------------------------------------------ Placement
variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The cluster is <name_prefix>-aurora."
  type        = string
}

variable "subnet_ids" {
  description = "Private-data subnet IDs."
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security group of the cluster (network module, rds)."
  type        = string
}

variable "proxy_security_group_id" {
  description = "Security group of RDS Proxy (network module, rds_proxy)."
  type        = string
}

# ------------------------------------------------------------------ Engine and capacity
variable "engine_version" {
  description = "Aurora PostgreSQL version (major.minor); minor upgrades are applied in the maintenance window."
  type        = string
  default     = "16.6"
}

variable "min_acu" {
  description = "Serverless v2 minimum capacity (ACU, 0.5 steps)."
  type        = number
  default     = 0.5
}

variable "max_acu" {
  description = "Serverless v2 maximum capacity (ACU)."
  type        = number
  default     = 8

  validation {
    condition     = var.max_acu >= 1 && var.max_acu <= 256
    error_message = "max_acu must be between 1 and 256."
  }
}

variable "instance_count" {
  description = "Cluster instances: 1 = writer only (dev), 2 = writer + reader in another AZ for failover (staging/prod)."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 3
    error_message = "instance_count must be 1, 2 or 3."
  }
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "mmm"
}

variable "master_username" {
  description = "Admin user name. The password is created and rotated by RDS in Secrets Manager."
  type        = string
  default     = "mmm_admin"
}

# ------------------------------------------------------------------ Resilience
variable "deletion_protection" {
  description = "Block deletion (prod)."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Automated backup / point-in-time-recovery window (1-35)."
  type        = number
  default     = 35
}

variable "apply_immediately" {
  description = "Apply changes now instead of in the maintenance window."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------ Encryption and logging
variable "kms_key_arn" {
  description = "KMS key for storage and Performance Insights (kms module, purpose rds)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key for the RDS-managed admin secret and the proxy secrets (kms module, purpose secrets)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the PostgreSQL log group (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the exported PostgreSQL logs."
  type        = number
  default     = 90
}

variable "pgaudit_log" {
  description = "pgaudit.log classes."
  type        = string
  default     = "ddl,role"
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for the monitoring and proxy roles."
  type        = string
}

# ------------------------------------------------------------------ RDS Proxy
variable "proxy_user_secret_arns" {
  description = "Secrets ({username,password}) of DB users that may log in through RDS Proxy, e.g. app and migration users. The admin secret is always added."
  type        = list(string)
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

variable "cluster_tags" {
  description = "Extra tags on the cluster only, e.g. { backup = \"true\" } for AWS Backup selection."
  type        = map(string)
  default     = {}
}

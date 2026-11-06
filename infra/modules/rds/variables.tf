# ------------------------------------------------------------------ Placement
variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The DB instance is <name_prefix>-postgres."
  type        = string
}

variable "subnet_ids" {
  description = "Private-data subnet IDs."
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security group of the DB instance (network module, rds)."
  type        = string
}

variable "proxy_security_group_id" {
  description = "Security group of RDS Proxy (network module, rds_proxy)."
  type        = string
}

# ------------------------------------------------------------------ Engine and size
variable "engine_version" {
  description = "PostgreSQL version (major.minor); minor upgrades are applied in the maintenance window."
  type        = string
  default     = "16.6"
}

variable "instance_class" {
  description = "DB instance class, e.g. db.t4g.medium (dev), db.r6g.large (staging), db.r6g.xlarge (prod)."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must start with db."
  }
}

variable "allocated_storage" {
  description = "Initial gp3 storage in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GiB."
  }
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB (must be larger than allocated_storage)."
  type        = number
  default     = 500
}

variable "multi_az" {
  description = "Standby in a second AZ with automatic failover (staging/prod)."
  type        = bool
  default     = true
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

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
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
  description = "KMS key for the PostgreSQL log groups (kms module, purpose logs)."
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

variable "instance_tags" {
  description = "Extra tags on the DB instance only, e.g. { backup = \"true\" } for AWS Backup selection."
  type        = map(string)
  default     = {}
}

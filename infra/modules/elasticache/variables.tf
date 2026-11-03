variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The replication group is <name_prefix>-redis."
  type        = string
}

variable "subnet_ids" {
  description = "Private-data subnet IDs."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group (network module, redis)."
  type        = string
}

variable "engine" {
  description = "valkey (default, cheaper) or redis."
  type        = string
  default     = "valkey"

  validation {
    condition     = contains(["valkey", "redis"], var.engine)
    error_message = "engine must be valkey or redis."
  }
}

variable "engine_version" {
  description = "Engine version (e.g. 8.0 for Valkey, 7.1 for Redis OSS)."
  type        = string
  default     = "8.0"
}

variable "node_type" {
  description = "Cache node type."
  type        = string
  default     = "cache.t4g.small"
}

variable "num_cache_clusters" {
  description = "1 = single node (dev); 2+ = primary + replicas with automatic failover and Multi-AZ."
  type        = number
  default     = 2
}

variable "auth_token" {
  description = "Auth token (secrets module, generated value of redis/token). 16-128 alphanumeric characters."
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key for data at rest and snapshots."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the slow-log / engine-log groups."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the cache log groups."
  type        = number
  default     = 30
}

variable "snapshot_retention_days" {
  description = "Daily snapshots kept (1 in dev, 7 in prod)."
  type        = number
  default     = 7
}

variable "apply_immediately" {
  description = "Apply changes now instead of in the maintenance window."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

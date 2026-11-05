variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "purposes" {
  description = "One customer-managed key is created per purpose; the alias is alias/<name_prefix>-<purpose>."
  type        = list(string)
  default     = ["rds", "s3", "logs", "secrets", "ecr", "sagemaker"]

  validation {
    condition     = alltrue([for p in var.purposes : can(regex("^[a-z0-9-]+$", p))])
    error_message = "Purposes may contain only lowercase letters, digits and hyphens."
  }
}

variable "logs_service_purposes" {
  description = "Purposes whose key policy also lets CloudWatch Logs in this account use the key (normally only logs)."
  type        = list(string)
  default     = ["logs"]
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion takes effect."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "additional_policy_documents" {
  description = "Extra key-policy JSON per purpose (e.g. Bedrock guardrail or Databricks access added in later steps)."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Extra tags for the keys."
  type        = map(string)
  default     = {}
}

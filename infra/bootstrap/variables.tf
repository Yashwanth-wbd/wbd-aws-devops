variable "environment" {
  description = "Environment this account hosts. Must match the selected Terraform workspace."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "aws_account_id" {
  description = "AWS account ID for this environment (12 digits)."
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

variable "enable_dynamodb_lock" {
  description = "Also create a DynamoDB lock table. Terraform >= 1.10 locks with an S3 lock file (use_lockfile), so this is only needed for older Terraform versions or if WBD requires it."
  type        = bool
  default     = false
}

variable "state_noncurrent_version_days" {
  description = "Days to keep old versions of state files before they expire."
  type        = number
  default     = 90
}

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

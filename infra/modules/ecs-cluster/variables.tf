variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The cluster is <name_prefix>-ecs."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the ECS Exec audit log group and ECS Exec session encryption (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the ECS Exec audit log group."
  type        = number
  default     = 365
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for the task execution role."
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager ARNs the execution role may inject into containers (only these; empty = none)."
  type        = list(string)
  default     = []
}

variable "parameter_path_arn" {
  description = "SSM parameter path the execution role may inject, e.g. arn:aws:ssm:<region>:<account>:parameter/mmm/dev/*."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key of the secrets and SecureString parameters."
  type        = string
}

variable "ecr_kms_key_arn" {
  description = "KMS key of the ECR repositories."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

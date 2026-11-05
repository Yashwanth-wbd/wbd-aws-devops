variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "name" {
  description = "Function name without prefix, e.g. results-publisher. The function is <name_prefix>-<name>."
  type        = string
}

variable "description" {
  description = "Function description."
  type        = string
}

variable "source_dir" {
  description = "Folder zipped as the first version. null = the module's seed handler (the app code is then shipped by deploy.yml)."
  type        = string
  default     = null
}

variable "handler" {
  description = "Handler (<file>.<function>)."
  type        = string
  default     = "handler.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 60
}

variable "memory_size" {
  description = "Memory in MiB."
  type        = number
  default     = 512
}

variable "reserved_concurrency" {
  description = "Concurrency cap (also protects the database from connection storms)."
  type        = number
  default     = 10
}

variable "environment" {
  description = "Non-secret environment variables."
  type        = map(string)
  default     = {}
}

variable "policy_json" {
  description = "Least-privilege policy of what the function calls. Logs, ENIs, X-Ray and the env-var key are added by the module."
  type        = string
}

variable "subnet_ids" {
  description = "Private-app subnets."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups of the function (network module)."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for the environment variables (kms module, purpose secrets)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key for the log group (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Log retention."
  type        = number
  default     = 30
}

variable "alarm_topic_arn" {
  description = "SNS topic of the errors alarm (monitoring module)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the function role."
  type        = string
}

variable "component" {
  description = "Component tag value."
  type        = string
  default     = "lambda"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

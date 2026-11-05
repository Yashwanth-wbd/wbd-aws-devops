variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "name" {
  description = "State machine name without prefix, e.g. optimization. The state machine is <name_prefix>-<name>."
  type        = string
}

variable "definition" {
  description = "Amazon States Language definition (JSON string)."
  type        = string
}

variable "role_policy_json" {
  description = "Least-privilege policy of what the states call (SageMaker, Lambda, SSM, ...). Log delivery and X-Ray are added by the module."
  type        = string
}

variable "include_execution_data" {
  description = "Log state input/output. Keep false when inputs may contain business data."
  type        = bool
  default     = false
}

variable "logs_kms_key_arn" {
  description = "KMS key for the log group (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Execution log retention."
  type        = number
  default     = 30
}

variable "alarm_topic_arn" {
  description = "SNS topic for the failed-execution alarm (monitoring module)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the state machine role."
  type        = string
}

variable "component" {
  description = "Component tag value."
  type        = string
  default     = "orchestration"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

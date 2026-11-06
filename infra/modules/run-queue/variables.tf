variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "state_machine_arn" {
  description = "Optimization state machine the dispatcher starts (step-functions module)."
  type        = string
}

variable "state_machine_name" {
  description = "Name of the optimization state machine (metric dimension)."
  type        = string
}

variable "max_runs_parameter_name" {
  description = "SSM parameter with the number of runs allowed at the same time (read on every batch)."
  type        = string
}

variable "max_runs_parameter_arn" {
  description = "ARN of max_runs_parameter_name."
  type        = string
}

variable "max_queue_wait_minutes" {
  description = "A request older than this is dropped and counted in ExpiredRunRequests."
  type        = number
  default     = 30

  validation {
    condition     = var.max_queue_wait_minutes >= 5 && var.max_queue_wait_minutes <= 720
    error_message = "max_queue_wait_minutes must be between 5 and 720."
  }
}

variable "max_receive_count" {
  description = "Receives before a request goes to the DLQ (keep maxReceiveCount x 6 x dispatcher_timeout above max_queue_wait_minutes)."
  type        = number
  default     = 10
}

variable "dispatcher_timeout" {
  description = "Dispatcher timeout in seconds; the queue visibility timeout is 6x this."
  type        = number
  default     = 60
}

variable "dispatcher_concurrency" {
  description = "Reserved concurrency of the dispatcher and maximum concurrency of the event source (2 = the SQS minimum; keeps the run count accurate)."
  type        = number
  default     = 2

  validation {
    condition     = var.dispatcher_concurrency >= 2
    error_message = "SQS event sources need a maximum concurrency of at least 2."
  }
}

variable "oldest_message_alarm_minutes" {
  description = "Alarm when the oldest waiting request is older than this."
  type        = number
  default     = 15
}

variable "metric_namespace" {
  description = "CloudWatch namespace of the dispatcher metrics (ExpiredRunRequests, RunningRuns)."
  type        = string
  default     = "MMM/Optimization"
}

variable "sqs_kms_key_arn" {
  description = "KMS key of both queues (kms module, purpose sqs)."
  type        = string
}

variable "env_kms_key_arn" {
  description = "KMS key of the Lambda environment variables (kms module, purpose secrets)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "KMS key of the log group (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Log retention."
  type        = number
  default     = 30
}

variable "subnet_ids" {
  description = "Private-app subnets."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group of the dispatcher (network module, lambda)."
  type        = string
}

variable "alarm_topic_arn" {
  description = "SNS topic of the alarms (monitoring module)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the dispatcher role."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

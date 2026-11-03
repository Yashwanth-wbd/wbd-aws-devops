variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. Queues are <name_prefix>-jobs.fifo and <name_prefix>-jobs-dlq.fifo."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key (kms module, purpose sqs)."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Must be longer than the longest optimizer / what-if job (15 min)."
  type        = number
  default     = 960

  validation {
    condition     = var.visibility_timeout_seconds > 900 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be > 900 (longest job) and <= 43200."
  }
}

variable "max_receive_count" {
  description = "Deliveries before a message moves to the DLQ."
  type        = number
  default     = 3
}

variable "message_retention_seconds" {
  description = "Job queue retention."
  type        = number
  default     = 345600
}

variable "dlq_retention_seconds" {
  description = "DLQ retention (maximum 14 days, to give time to investigate)."
  type        = number
  default     = 1209600
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

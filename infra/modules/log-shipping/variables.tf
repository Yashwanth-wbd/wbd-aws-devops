variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "enabled" {
  description = "Create the Firehose stream and subscriptions. Keep false until the Splunk HEC endpoint and token exist."
  type        = bool
  default     = false
}

variable "hec_endpoint" {
  description = "Splunk HEC URL, e.g. https://http-inputs-wbd.splunkcloud.com:443 (must be reachable from the Firehose IP ranges of the region)."
  type        = string
}

variable "hec_endpoint_type" {
  description = "Raw or Event HEC endpoint."
  type        = string
  default     = "Raw"

  validation {
    condition     = contains(["Raw", "Event"], var.hec_endpoint_type)
    error_message = "hec_endpoint_type must be Raw or Event."
  }
}

variable "hec_secret_arn" {
  description = "Secrets Manager secret holding {\"hec_token\": \"...\"}; Firehose reads it at delivery time."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key of the HEC secret."
  type        = string
}

variable "log_group_names" {
  description = "Log groups shipped to Splunk (key => log group name). Same region as the stack."
  type        = map(string)
}

variable "extract_messages" {
  description = "true = send only each log line; false = send the CloudWatch envelope (logGroup, logStream, logEvents) so Splunk knows the source."
  type        = bool
  default     = false
}

variable "failed_records_bucket_arn" {
  description = "Bucket for records Splunk did not accept (the log bucket)."
  type        = string
}

variable "failed_records_prefix" {
  description = "Prefix for failed records."
  type        = string
  default     = "splunk-failed"
}

variable "logs_kms_key_arn" {
  description = "Key for the stream, its error log group and the failed records."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the Firehose error log group."
  type        = number
  default     = 365
}

variable "permissions_boundary_arn" {
  description = "Boundary for the Firehose and CloudWatch Logs roles."
  type        = string
}

variable "alert_topic_arn" {
  description = "SNS topic for delivery alarms."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

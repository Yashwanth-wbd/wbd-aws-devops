variable "bucket_name" {
  description = "Bucket name, e.g. wbd-mmm-dev-logs-use1."
  type        = string
}

variable "retention_days" {
  description = "Days log objects are kept before they expire."
  type        = number
  default     = 365
}

variable "noncurrent_version_days" {
  description = "Days an overwritten or deleted log version is kept."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

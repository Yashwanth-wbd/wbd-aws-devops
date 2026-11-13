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

variable "cloudtrail_trail_arn" {
  description = "ARN of a CloudTrail trail allowed to deliver to cloudtrail/ (the optional S3 data-events trail). null = no CloudTrail delivery."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

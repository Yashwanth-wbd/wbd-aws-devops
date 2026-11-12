variable "bucket_name" {
  description = "Bucket name, e.g. wbd-mmm-dev-results-use1."
  type        = string
}

variable "kms_key_arn" {
  description = "Default SSE-KMS key (kms module, purpose s3)."
  type        = string
}

variable "access_log_bucket" {
  description = "Bucket that receives S3 server access logs (log-bucket module)."
  type        = string
}

variable "access_log_prefix" {
  description = "Prefix in the log bucket; the bucket name is appended."
  type        = string
  default     = "s3-access/"
}

variable "additional_kms_key_arns" {
  description = "Other KMS keys uploads may ask for (e.g. the per-business-unit keys of the landing bucket)."
  type        = list(string)
  default     = []
}

variable "deny_non_kms_uploads" {
  description = "Bucket policy rejects uploads that ask for SSE-S3, SSE-C or a different KMS key."
  type        = bool
  default     = true
}

variable "object_lock" {
  description = "WORM default retention, e.g. { mode = \"COMPLIANCE\", days = 2555 }. null = no Object Lock. Can only be turned on when the bucket is created."
  type = object({
    mode = string
    days = number
  })
  default = null

  validation {
    condition     = var.object_lock == null || try(contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock.mode) && var.object_lock.days > 0, false)
    error_message = "object_lock.mode must be GOVERNANCE or COMPLIANCE and days > 0."
  }
}

variable "expiration_days" {
  description = "Delete current objects after this many days (null = keep)."
  type        = number
  default     = null
}

variable "prefix_expiration_days" {
  description = "Extra expiry for short-lived prefixes: prefix (ending in /) => days, e.g. { \"monitoring/\" = 90 }."
  type        = map(number)
  default     = {}
}

variable "glacier_transition_days" {
  description = "Move current objects to S3 Glacier Flexible Retrieval after this many days (null = never)."
  type        = number
  default     = null
}

variable "noncurrent_version_days" {
  description = "Delete overwritten or deleted object versions after this many days."
  type        = number
  default     = 90
}

variable "enable_eventbridge" {
  description = "Send object events to EventBridge (used by the data trigger in Step 13)."
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "Origins (https://<app domain>) allowed to PUT / GET with presigned URLs from the browser. Empty = no CORS configuration."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : startswith(o, "https://") && o != "https://*"])
    error_message = "cors_allowed_origins must be https origins (no wildcard)."
  }
}

variable "additional_policy_json" {
  description = "Extra bucket-policy JSON merged in (e.g. cross-account read for Databricks)."
  type        = string
  default     = ""
}

variable "replication" {
  description = "Cross-region replication to an existing DR bucket. null = off."
  type = object({
    destination_bucket_arn   = string
    destination_kms_key_arn  = string
    permissions_boundary_arn = string
  })
  default = null
}

variable "component" {
  description = "Component tag value."
  type        = string
  default     = "s3"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "databricks_host" {
  description = "Databricks workspace URL (https://...)."
  type        = string

  validation {
    condition     = startswith(var.databricks_host, "https://")
    error_message = "databricks_host must be an https URL."
  }
}

variable "service_principal_secret_arn" {
  description = "Secrets Manager secret {\"client_id\", \"client_secret\"} of the Databricks service principal that may run the export jobs (filled out-of-band, docs/05)."
  type        = string
}

variable "job_ids_parameter_name" {
  description = "SSM parameter holding {\"<bu>\": <export job id>} (from WBD Databricks)."
  type        = string
}

variable "job_ids_parameter_arn" {
  description = "ARN of job_ids_parameter_name."
  type        = string
}

variable "landing_bucket_arn" {
  description = "Landing bucket; the Lambda writes only _manifest.json files under manifest_prefix."
  type        = string
}

variable "manifest_prefix" {
  description = "Prefix (ending in /) under which the export output and its _manifest.json live."
  type        = string
  default     = "raw/databricks/"
}

variable "business_unit_keys" {
  description = "Business unit => KMS key ARN the manifest of that unit is encrypted with (the landing bucket policy requires it)."
  type        = map(string)
}

variable "default_key_arn" {
  description = "Key for a manifest of a business unit without its own key (s3 key)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "Key of the service-principal secret and of the Lambda environment."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Key of the Lambda log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the Lambda log group."
  type        = number
  default     = 30
}

variable "timeout" {
  description = "Lambda timeout in seconds (one Jobs API call plus the token request)."
  type        = number
  default     = 60
}

variable "subnet_ids" {
  description = "Private-app subnets (NAT or PrivateLink to the workspace)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups (network module: databricks_export)."
  type        = list(string)
}

variable "alarm_topic_arn" {
  description = "SNS topic of the errors alarm."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the Lambda role."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "selection_tag" {
  description = "Resources with this tag key = \"true\" are backed up (RDS, S3 buckets)."
  type        = string
  default     = "backup"
}

variable "schedule" {
  description = "Daily backup time (cron, UTC). After the RDS backup window (02:00-03:00 UTC)."
  type        = string
  default     = "cron(0 4 * * ? *)"
}

variable "daily_retention_days" {
  description = "How long daily recovery points are kept."
  type        = number
  default     = 35
}

variable "monthly_retention_days" {
  description = "Keep the 1st-of-month backup this long (null = no monthly rule)."
  type        = number
  default     = null
}

variable "deny_manual_deletion" {
  description = "Vault policy denying manual deletion of recovery points (only expiry removes them). false in dev so the vault can be emptied and destroyed."
  type        = bool
  default     = true
}

variable "vault_lock" {
  description = <<-EOT
    Vault lock (prod). null = no lock. After changeable_for_days the lock is in COMPLIANCE mode and
    can NEVER be removed, not even by the root user; recovery points cannot be deleted early.
  EOT
  type = object({
    min_retention_days  = number
    max_retention_days  = number
    changeable_for_days = number
  })
  default = null
}

variable "enable_cross_region_copy" {
  description = "Copy every recovery point to a vault in the DR region (aws.dr provider)."
  type        = bool
  default     = false
}

variable "dr_retention_days" {
  description = "Retention of the copies in the DR region."
  type        = number
  default     = 35
}

variable "permissions_boundary_arn" {
  description = "Boundary for the AWS Backup role."
  type        = string
}

variable "alert_topic_arn" {
  description = "SNS topic for failed backup, copy and restore jobs."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

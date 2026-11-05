variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The web ACL is <name_prefix>-alb."
  type        = string
}

variable "alb_arn" {
  description = "ALB the web ACL protects."
  type        = string
}

variable "rate_limit" {
  description = "Requests per 5 minutes per IP before blocking."
  type        = number
  default     = 2000
}

variable "geo_allow_countries" {
  description = "Countries allowed to reach the app (ISO codes). Empty = no geo restriction."
  type        = list(string)
  default     = []
}

variable "count_only_rules" {
  description = "Rules of AWSManagedRulesCommonRuleSet switched to count (e.g. SizeRestrictions_BODY for large plan uploads)."
  type        = list(string)
  default     = []
}

variable "logs_kms_key_arn" {
  description = "KMS key for the WAF log group (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "WAF log retention."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

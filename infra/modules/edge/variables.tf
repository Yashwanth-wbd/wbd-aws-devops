variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "aliases" {
  description = "Custom domain names of the app (must be covered by certificate_arn). DNS records are created by WBD DNS for now."
  type        = list(string)

  validation {
    condition     = length(var.aliases) > 0
    error_message = "At least one alias is needed: TLS 1.2 as the minimum viewer protocol requires a custom certificate."
  }
}

variable "certificate_arn" {
  description = "ACM certificate in us-east-1 that covers every alias."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:us-east-1:", var.certificate_arn))
    error_message = "CloudFront certificates must be in us-east-1."
  }
}

variable "frontend_bucket_regional_domain_name" {
  description = "Regional domain name of the frontend bucket (S3 origin, read through OAC)."
  type        = string
}

variable "alb_origin_domain_name" {
  description = "Origin host name of the ALB (the name on alb_certificate_arn, CNAME to the ALB DNS name). CloudFront checks the ALB certificate against it."
  type        = string
}

variable "origin_verify_value" {
  description = "Value of the X-Origin-Verify header CloudFront adds; the ALB forwards only requests that carry it."
  type        = string
  sensitive   = true
}

variable "api_path_pattern" {
  description = "Path pattern routed to the ALB."
  type        = string
  default     = "/api/*"
}

variable "origin_read_timeout" {
  description = "Seconds CloudFront waits for the API (long jobs go through SQS, so 60 is enough)."
  type        = number
  default     = 60
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "geo_allow_countries" {
  description = "ISO country codes allowed to reach the app. Empty list = no geo restriction."
  type        = list(string)
  default     = []
}

variable "content_security_policy" {
  description = "Content-Security-Policy header. null builds one that allows only this site and the Okta domain."
  type        = string
  default     = null
}

variable "okta_issuer" {
  description = "Okta issuer URL; its host is allowed in the default Content-Security-Policy."
  type        = string
}

variable "initial_release" {
  description = "Release folder served before the first frontend deploy (frontend-ci.yml changes the value afterwards)."
  type        = string
  default     = "seed"
}

variable "access_log_bucket_domain_name" {
  description = "Log bucket domain name (<bucket>.s3.amazonaws.com) for CloudFront standard logs."
  type        = string
}

variable "access_log_prefix" {
  description = "Prefix in the log bucket."
  type        = string
  default     = "cloudfront"
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per client IP before the WAF blocks it."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 100
    error_message = "WAF rate limits start at 100 requests per 5 minutes."
  }
}

variable "waf_count_only_rules" {
  description = "Managed CommonRuleSet rules that only count instead of block. SizeRestrictions_BODY blocks bodies over 8 KB, which scenario payloads can exceed; the API enforces its own limit."
  type        = list(string)
  default     = ["SizeRestrictions_BODY"]
}

variable "waf_log_retention_days" {
  description = "Retention of the WAF log group."
  type        = number
  default     = 365
}

variable "create_waf_log_kms_key" {
  description = "Create a dedicated KMS key in us-east-1 for the WAF log group. false = use waf_log_kms_key_arn. A plain bool, so count is known at plan time even when the ARN is not."
  type        = bool
  default     = true
}

variable "waf_log_kms_key_arn" {
  description = "Existing KMS key in us-east-1 for the WAF log group (only when create_waf_log_kms_key = false)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

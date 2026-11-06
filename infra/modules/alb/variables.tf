variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The ALB is <name_prefix>-alb."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (one per AZ)."
  type        = list(string)
}

variable "security_group_id" {
  description = "ALB security group (network module, alb)."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate in this region for the app host name."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "oidc" {
  description = "OIDC sign-in at the ALB (WBD Okta app of this environment). Endpoints come from <issuer>/.well-known/openid-configuration. null = no sign-in: the ALB answers 503 (except the health path) unless allow_unauthenticated."
  type = object({
    issuer                 = string
    authorization_endpoint = string
    token_endpoint         = string
    user_info_endpoint     = string
    client_id              = string
    scope                  = optional(string, "openid profile email groups")
    session_seconds        = optional(number, 43200)
  })
  default = null
}

variable "allow_unauthenticated" {
  description = "Without oidc, forward to the targets with no sign-in (isolated tests only - never on an internet-facing environment)."
  type        = bool
  default     = false
}

variable "oidc_client_secret" {
  description = "Client secret of the Okta app (read from Secrets Manager by the stack, never a tfvars value). Required when oidc is set."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_port" {
  description = "API container port."
  type        = number
  default     = 8080
}

variable "ui_port" {
  description = "UI container port."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "API health endpoint (reachable without login)."
  type        = string
  default     = "/api/health"
}

variable "ui_health_check_path" {
  description = "UI health endpoint (target group health check only)."
  type        = string
  default     = "/healthz"
}

variable "access_log_bucket" {
  description = "Log bucket (log-bucket module)."
  type        = string
}

variable "access_log_prefix" {
  description = "Prefix in the log bucket (log-bucket module prefixes.alb)."
  type        = string
  default     = "alb"
}

variable "deletion_protection" {
  description = "Block deletion of the ALB (prod)."
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "Idle timeout in seconds."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

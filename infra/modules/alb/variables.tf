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
  description = "ALB security group (network module, alb): HTTPS from CloudFront only."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate in this region for the ALB origin hostname (CloudFront checks it)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "origin_verify_value" {
  description = "Shared secret CloudFront sends in X-Origin-Verify (secrets module, edge/origin-verify)."
  type        = string
  sensitive   = true
}

variable "app_port" {
  description = "API container port."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "API health endpoint."
  type        = string
  default     = "/api/health"
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

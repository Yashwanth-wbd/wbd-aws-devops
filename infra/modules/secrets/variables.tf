variable "path_prefix" {
  description = "Path for secret and parameter names, e.g. mmm/dev -> secret mmm/dev/api/db, parameter /mmm/dev/genai_enabled."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+(/[a-z0-9-]+)*$", var.path_prefix))
    error_message = "path_prefix must be lowercase segments separated by '/', with no leading or trailing '/'."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for secrets and SecureString parameters (kms module, purpose secrets)."
  type        = string
}

variable "secrets" {
  description = <<-EOT
    Secrets to create, keyed by the name under path_prefix (e.g. "api/db").
    generate = false: empty container, filled out-of-band by DevOps.
    generate = true:  Terraform generates a random alphanumeric value of `length` characters.
  EOT
  type = map(object({
    description = string
    generate    = optional(bool, false)
    length      = optional(number, 64)
  }))

  validation {
    condition     = alltrue([for k, s in var.secrets : can(regex("^[a-z0-9_-]+(/[a-z0-9_-]+)*$", k)) && s.length >= 32 && s.length <= 128])
    error_message = "Secret keys must be lowercase path segments (letters, digits, '_' or '-'); length must be 32-128."
  }
}

variable "generated_secret_rotation_id" {
  description = "Change this value (e.g. to a date) to regenerate every generated secret on the next apply."
  type        = string
  default     = "initial"
}

variable "recovery_window_in_days" {
  description = "Days a deleted secret can still be restored (7-30)."
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30
    error_message = "recovery_window_in_days must be between 7 and 30."
  }
}

variable "parameters" {
  description = "SSM parameters keyed by the name under /path_prefix (e.g. \"okta/issuer\"). Values must not be secrets."
  type = map(object({
    value       = string
    description = string
    secure      = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, p in var.parameters : can(regex("^[a-z0-9_-]+(/[a-z0-9_-]+)*$", k))])
    error_message = "Parameter keys must be lowercase path segments (letters, digits, '_' or '-')."
  }
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

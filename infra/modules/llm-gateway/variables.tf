variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The API is <name_prefix>-llm-gateway."
  type        = string
}

variable "llm_providers" {
  description = "Approved providers: name => { base_url, auth = bearer | x-api-key | x-goog-api-key }. Only these paths are forwarded."
  type = map(object({
    base_url = string
    auth     = string
  }))

  validation {
    condition     = alltrue([for p in values(var.llm_providers) : can(regex("^https://", p.base_url)) && contains(["bearer", "x-api-key", "x-goog-api-key"], p.auth)])
    error_message = "Each provider needs an https base_url and auth bearer, x-api-key or x-goog-api-key."
  }
}

variable "provider_secret_arns" {
  description = "Secrets Manager secret per provider ({\"api_key\": \"...\"}, filled by DevOps)."
  type        = map(string)
}

variable "guardrail_id" {
  description = "Bedrock guardrail ID (bedrock-guardrails module)."
  type        = string
}

variable "guardrail_arn" {
  description = "Bedrock guardrail ARN."
  type        = string
}

variable "guardrail_version" {
  description = "Pinned guardrail version."
  type        = string
}

variable "guardrail_kms_key_arn" {
  description = "Key that encrypts the guardrail."
  type        = string
}

variable "invoker_role_arns" {
  description = "Roles allowed to call the gateway (API task role)."
  type        = list(string)
}

variable "vpc_endpoint_id" {
  description = "execute-api interface endpoint (network module)."
  type        = string
}

variable "subnet_ids" {
  description = "Private-app subnets of the proxy Lambda (internet egress through NAT to the providers)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group of the proxy Lambda (network module, genai)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "Key of the provider secrets and the Lambda environment (kms module, purpose secrets)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Key of the log groups (kms module, purpose logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Log retention."
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = "Concurrency cap of the proxy (cost and provider rate-limit protection)."
  type        = number
  default     = 50
}

variable "throttle_rate_per_second" {
  description = "Stage-wide steady request rate."
  type        = number
  default     = 20
}

variable "throttle_burst" {
  description = "Stage-wide burst."
  type        = number
  default     = 40
}

variable "error_alarm_threshold" {
  description = "5xx responses per 5 minutes that raise the alarm."
  type        = number
  default     = 5
}

variable "client_error_alarm_threshold" {
  description = "4xx responses per 5 minutes that raise the alarm."
  type        = number
  default     = 20
}

variable "latency_p95_ms" {
  description = "p95 gateway latency (ms) that raises the alarm."
  type        = number
  default     = 30000
}

variable "manage_account_logging_role" {
  description = "Set the account-level API Gateway CloudWatch role (false if WBD already manages it)."
  type        = bool
  default     = true
}

variable "alarm_topic_arn" {
  description = "SNS topic of the alarms (monitoring module)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the roles."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

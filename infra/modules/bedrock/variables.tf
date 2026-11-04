# ------------------------------------------------------------------ General
variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "environment" {
  description = "dev, staging or prod (dimension of the gateway's MMM/GenAI metrics)."
  type        = string
}

variable "approved_model_ids" {
  description = "Bedrock model IDs WBD approved (foundation model or cross-region inference profile, e.g. us.anthropic...). Nothing else can be invoked."
  type        = list(string)

  validation {
    condition     = length(var.approved_model_ids) > 0 && alltrue([for id in var.approved_model_ids : can(regex("^[a-z0-9][a-z0-9.:-]+$", id))])
    error_message = "approved_model_ids needs at least one model ID such as anthropic.claude-3-5-sonnet-20240620-v1:0."
  }
}

variable "kms_key_arn" {
  description = "Customer-managed key for the guardrail, the invocation-log bucket and log group (kms module, purpose genai)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary for the invocation-logging role."
  type        = string
}

variable "tags" {
  description = "Extra tags; the module adds Component = genai."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------ PrivateLink
variable "vpc_id" {
  description = "VPC of the gateway tasks."
  type        = string
}

variable "endpoint_subnet_ids" {
  description = "Private-endpoint subnets (network module)."
  type        = list(string)
}

variable "endpoint_security_group_id" {
  description = "Security group of the interface endpoints (HTTPS from the VPC)."
  type        = string
}

variable "invoker_role_arns" {
  description = "Roles allowed through the endpoint policy (the GenAI gateway task role)."
  type        = list(string)
}

# ------------------------------------------------------------------ Guardrail
variable "guardrail_version_label" {
  description = "Change (e.g. v2) to publish a new guardrail version after a policy change."
  type        = string
  default     = "v1"
}

variable "prompt_attack_strength" {
  description = "Prompt-attack (jailbreak / injection) filter strength on input."
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["NONE", "LOW", "MEDIUM", "HIGH"], var.prompt_attack_strength)
    error_message = "prompt_attack_strength must be NONE, LOW, MEDIUM or HIGH."
  }
}

variable "content_filter_strength" {
  description = "Strength of the hate, insults, sexual, violence and misconduct filters (input and output)."
  type        = string
  default     = "MEDIUM"

  validation {
    condition     = contains(["NONE", "LOW", "MEDIUM", "HIGH"], var.content_filter_strength)
    error_message = "content_filter_strength must be NONE, LOW, MEDIUM or HIGH."
  }
}

variable "pii_anonymize_types" {
  description = "PII types masked in prompts and answers."
  type        = list(string)
  default     = ["EMAIL", "PHONE", "NAME", "ADDRESS"]
}

variable "pii_block_types" {
  description = "PII and credential types that block the request or answer."
  type        = list(string)
  default     = ["US_SOCIAL_SECURITY_NUMBER", "CREDIT_DEBIT_CARD_NUMBER", "US_BANK_ACCOUNT_NUMBER", "AWS_ACCESS_KEY", "AWS_SECRET_KEY", "PASSWORD"]
}

variable "grounding_threshold" {
  description = "Contextual grounding: answers scoring below this against the supplied sources are blocked (0-0.99)."
  type        = number
  default     = 0.75

  validation {
    condition     = var.grounding_threshold >= 0 && var.grounding_threshold < 1
    error_message = "grounding_threshold must be between 0 and 0.99."
  }
}

variable "relevance_threshold" {
  description = "Contextual relevance: answers scoring below this against the question are blocked (0-0.99)."
  type        = number
  default     = 0.75

  validation {
    condition     = var.relevance_threshold >= 0 && var.relevance_threshold < 1
    error_message = "relevance_threshold must be between 0 and 0.99."
  }
}

variable "blocked_input_message" {
  description = "Returned when the guardrail blocks a prompt."
  type        = string
  default     = "This request cannot be processed by the MMM assistant. Please rephrase it without personal or sensitive data."
}

variable "blocked_output_message" {
  description = "Returned when the guardrail blocks an answer."
  type        = string
  default     = "The MMM assistant could not produce an answer supported by the model results. Please check the scenario data directly."
}

# ------------------------------------------------------------------ Invocation logging
variable "enable_invocation_logging" {
  description = "Configure Bedrock model invocation logging (one setting per account and region; off if WBD manages it centrally)."
  type        = bool
  default     = true
}

variable "invocation_log_bucket_name" {
  description = "Bucket for invocation logs, e.g. wbd-mmm-dev-genai-logs-use1."
  type        = string
}

variable "invocation_log_prefix" {
  description = "Key prefix of the invocation logs."
  type        = string
  default     = "bedrock-invocations"
}

variable "invocation_log_s3_days" {
  description = "Days invocation logs are kept in S3."
  type        = number
  default     = 400
}

variable "access_log_bucket" {
  description = "Bucket that receives S3 server access logs (log-bucket module)."
  type        = string
}

variable "access_log_prefix" {
  description = "Prefix for S3 access logs in the log bucket."
  type        = string
  default     = "s3-access/"
}

variable "log_retention_days" {
  description = "Retention of the invocation log group."
  type        = number
  default     = 90
}

# ------------------------------------------------------------------ Monitoring and cost
variable "alert_topic_arn" {
  description = "SNS topic for the GenAI alarms (monitoring module)."
  type        = string
  default     = null
}

variable "ecs_cluster_name" {
  description = "Cluster of the gateway service (dashboard)."
  type        = string
}

variable "gateway_service_name" {
  description = "ECS service name of the gateway (dashboard)."
  type        = string
}

variable "gateway_log_group_name" {
  description = "Log group of the gateway (dashboard errors widget)."
  type        = string
}

variable "token_quotas" {
  description = "Daily token quota per business unit; one alarm per BU plus one on the total."
  type        = map(number)
  default     = {}
}

variable "server_error_threshold" {
  description = "Server errors per 5 minutes (3 periods in a row) that raise an alarm."
  type        = number
  default     = 0
}

variable "client_error_threshold" {
  description = "Client errors per 5 minutes (3 periods in a row) that raise an alarm."
  type        = number
  default     = 5
}

variable "throttle_threshold" {
  description = "Throttled calls per 5 minutes (3 periods in a row) that raise an alarm."
  type        = number
  default     = 5
}

variable "latency_p95_ms" {
  description = "p95 model latency (ms) that raises an alarm."
  type        = number
  default     = 20000
}

variable "monthly_budget_usd" {
  description = "Monthly GenAI (Bedrock) cost budget; alerts at 50/80/100 % actual and 100 % forecast."
  type        = number
}

variable "budget_alert_emails" {
  description = "Recipients of the GenAI budget alerts."
  type        = list(string)
}

variable "budget_service_names" {
  description = "Cost Explorer service names counted by the GenAI budget (Amazon Bedrock plus the Marketplace names of third-party models)."
  type        = list(string)
  default     = ["Amazon Bedrock"]
}

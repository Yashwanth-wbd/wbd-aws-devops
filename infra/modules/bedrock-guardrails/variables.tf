variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The guardrail is <name_prefix>-genai."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key that encrypts the guardrail (kms module, purpose genai)."
  type        = string
}

variable "version_label" {
  description = "Change (v1 -> v2) to publish a new guardrail version after a policy change."
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

variable "intervention_alarm_threshold" {
  description = "Blocked prompts/answers per 15 minutes that raise the alarm."
  type        = number
  default     = 25
}

variable "alarm_topic_arn" {
  description = "SNS topic of the alarm (monitoring module)."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

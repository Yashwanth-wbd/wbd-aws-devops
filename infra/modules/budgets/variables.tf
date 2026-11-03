variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "monthly_limit_usd" {
  description = "Monthly cost budget for the account in USD."
  type        = number

  validation {
    condition     = var.monthly_limit_usd > 0
    error_message = "monthly_limit_usd must be greater than 0."
  }
}

variable "actual_thresholds_percent" {
  description = "Alert when actual spend passes these percentages of the budget."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "alert_emails" {
  description = "Email addresses for budget and anomaly alerts."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one alert email is required."
  }
}

variable "sns_topic_arn" {
  description = "Optional SNS topic for budget alerts (the monitoring topic from Step 9)."
  type        = string
  default     = null
}

variable "enable_anomaly_detection" {
  description = "Create a Cost Anomaly Detection monitor and daily email subscription."
  type        = bool
  default     = true
}

variable "anomaly_threshold_usd" {
  description = "Only report anomalies with at least this total cost impact (USD)."
  type        = number
  default     = 100
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

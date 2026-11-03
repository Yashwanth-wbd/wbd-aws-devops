variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "allowed_regions" {
  description = "Regions roles may use. Include us-east-1 (CloudFront certificates and WAF) and the DR region if one is approved."
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "At least one region must be allowed."
  }
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

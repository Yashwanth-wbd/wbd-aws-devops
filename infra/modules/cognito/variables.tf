variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The user pool is <name_prefix>-users."
  type        = string
}

variable "app_domain_name" {
  description = "App host name (e.g. mmm-dev.example.wbd.com); callback https://<name>/oauth2/idpresponse is the ALB."
  type        = string
}

variable "domain_prefix" {
  description = "Cognito hosted domain prefix (<prefix>.auth.<region>.amazoncognito.com); globally unique per region."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", var.domain_prefix)) && !can(regex("aws|amazon|cognito", var.domain_prefix))
    error_message = "domain_prefix: lowercase letters, digits and hyphens; must not contain aws, amazon or cognito."
  }
}

variable "idp_name" {
  description = "Name of the federated IdP in the user pool (shown in logs and the user name prefix)."
  type        = string
  default     = "WBD-Okta"
}

variable "saml_metadata_url" {
  description = "SAML metadata URL of the WBD Okta app for this environment (public, no secret)."
  type        = string

  validation {
    condition     = can(regex("^https://", var.saml_metadata_url))
    error_message = "saml_metadata_url must be an https URL."
  }
}

variable "saml_attribute_email" {
  description = "SAML attribute that carries the e-mail address."
  type        = string
  default     = "email"
}

variable "saml_attribute_name" {
  description = "SAML attribute that carries the display name."
  type        = string
  default     = "name"
}

variable "saml_attribute_groups" {
  description = "SAML attribute that carries the user's Okta groups (mapped to custom:groups)."
  type        = string
  default     = "groups"
}

variable "session_hours" {
  description = "Refresh-token lifetime in hours (how long a planner stays signed in)."
  type        = number
  default     = 12
}

variable "deletion_protection" {
  description = "Block deletion of the user pool (prod)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

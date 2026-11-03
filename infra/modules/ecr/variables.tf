variable "repositories" {
  description = "Repository names in this account's registry."
  type        = list(string)
  default     = ["mmm/api", "mmm/optimizer-worker", "mmm/genai-gateway"]

  validation {
    condition     = alltrue([for r in var.repositories : can(regex("^mmm/[a-z0-9-]+$", r))])
    error_message = "Repository names must look like mmm/<name> (the pipeline roles are scoped to repository/mmm/*)."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for image encryption (kms module, purpose ecr)."
  type        = string
}

variable "enhanced_scanning" {
  description = "Registry-wide Amazon Inspector enhanced scanning (continuous). false = basic scan on push."
  type        = bool
  default     = true
}

variable "untagged_expiry_days" {
  description = "Delete untagged images after this many days."
  type        = number
  default     = 7
}

variable "keep_sha_images" {
  description = "Number of sha-<7> build images kept per repository (dev builds; staging/prod receive only release tags)."
  type        = number
  default     = 30
}

variable "keep_release_images" {
  description = "Number of release images (v* tags) kept per repository."
  type        = number
  default     = 50
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

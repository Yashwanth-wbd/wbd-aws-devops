variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "allowed_regions" {
  description = "Regions roles may use. The workload region (ACM, Bedrock are regional) and the DR region if one is approved."
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "At least one region must be allowed."
  }
}

variable "bedrock_inference_regions" {
  description = "Extra regions where only bedrock:InvokeModel / InvokeModelWithResponseStream are allowed: the destination regions of the Bedrock cross-region inference profile (e.g. us.* = us-east-1, us-east-2, us-west-2). Empty = allowed_regions only."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

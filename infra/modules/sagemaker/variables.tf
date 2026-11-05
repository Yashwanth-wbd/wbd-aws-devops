variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "name" {
  description = "Job family, e.g. optimization or training. The role is <name_prefix>-sagemaker-<name>."
  type        = string
}

variable "read_bucket_arns" {
  description = "Buckets the jobs read (inputs, models, response curves)."
  type        = list(string)
}

variable "write_bucket_arns" {
  description = "Buckets the jobs write (run evidence, model artifacts)."
  type        = list(string)
  default     = []
}

variable "data_kms_key_arns" {
  description = "Keys of those buckets."
  type        = list(string)
}

variable "volume_kms_key_arn" {
  description = "Key for the job's ML storage volume and output (kms module, purpose sagemaker)."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repositories of the job images."
  type        = list(string)
}

variable "model_package_groups" {
  description = "Business units that get a model package group <name_prefix>-<bu> (training side). Empty = none."
  type        = list(string)
  default     = []
}

variable "notification_topic_arn" {
  description = "SNS topic for model package state changes (needed when model_package_groups is set)."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the execution role."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

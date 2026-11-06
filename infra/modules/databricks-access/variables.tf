variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID (external ID of the Unity Catalog role trust)."
  type        = string
}

variable "uc_master_role_arn" {
  description = "Databricks Unity Catalog master role that assumes the storage-credential role (Databricks docs, AWS commercial)."
  type        = string
  default     = "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
}

variable "self_assume_enabled" {
  description = "Phase 2: add the self-assume trust Databricks requires. Set true only after the role exists and the storage credential is registered."
  type        = bool
  default     = false
}

variable "bucket_arns" {
  description = "Buckets Unity Catalog reads and writes (landing, lakehouse, training-data)."
  type        = list(string)
}

variable "read_only_prefixes" {
  description = "Extra read-only access for Unity Catalog: { bucket_arn, prefix } (e.g. the models bucket evaluation/ for the write-back job)."
  type = list(object({
    bucket_arn = string
    prefix     = string
  }))
  default = []
}

variable "kms_key_arns" {
  description = "Keys of those buckets (s3 key and per-business-unit keys)."
  type        = list(string)
}

variable "enable_privatelink" {
  description = "Create the workspace PrivateLink endpoint and private DNS (needs the real endpoint service name from WBD Databricks)."
  type        = bool
  default     = false
}

variable "workspace_host" {
  description = "Workspace URL, e.g. https://dbc-xxxxxxxx-xxxx.cloud.databricks.com (private zone name)."
  type        = string
}

variable "workspace_service_name" {
  description = "Databricks workspace (REST API) VPC endpoint service name for the region."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC of the endpoint and private zone."
  type        = string
}

variable "endpoint_subnet_ids" {
  description = "Private-endpoint subnets."
  type        = list(string)
}

variable "endpoint_security_group_id" {
  description = "Security group of the endpoint (network module, endpoints: HTTPS from the VPC)."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the Unity Catalog role."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

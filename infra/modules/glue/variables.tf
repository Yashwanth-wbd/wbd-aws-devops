variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. Jobs are <name_prefix>-glue-<job>; databases <name_prefix with _>_bronze / _silver / _gold."
  type        = string
}

variable "environment" {
  description = "dev, staging or prod (job argument --ENV)."
  type        = string
}

variable "business_units" {
  description = "Business units; one refresh per BU can run at the same time, so this is the job concurrency."
  type        = list(string)
}

# ------------------------------------------------------------------ Buckets and keys
variable "assets_bucket_name" {
  description = "glue-assets bucket: scripts/<job>.py (released by glue.yml), temp/ (Spark shuffle / TempDir)."
  type        = string
}

variable "landing_bucket_name" {
  description = "Landing bucket; the Bronze job reads raw/databricks/<bu>/<date>/ (read only)."
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Lakehouse bucket: Delta tables bronze/, silver/, gold/ and monitoring/ exports."
  type        = string
}

variable "training_data_bucket_name" {
  description = "Training-data bucket (Object Lock): export-training writes the immutable Parquet snapshot + metadata."
  type        = string
}

variable "data_kms_key_arns" {
  description = "Keys of the data buckets (s3 key and per-business-unit keys)."
  type        = list(string)
}

variable "s3_kms_key_arn" {
  description = "Key of Glue's own S3 writes (security configuration) and job bookmarks."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Key of the Glue log group and of CloudWatch encryption in the security configuration."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the Glue job log group."
  type        = number
  default     = 30
}

# ------------------------------------------------------------------ Jobs
variable "glue_version" {
  description = "Glue version (5.0 = Spark 3.5, Python 3.11, Delta Lake via --datalake-formats)."
  type        = string
  default     = "5.0"
}

variable "worker_type" {
  description = "Worker type (G.1X = 4 vCPU / 16 GB, G.2X = 8 vCPU / 32 GB)."
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Workers per job run (2-299)."
  type        = number
  default     = 2

  validation {
    condition     = var.number_of_workers >= 2
    error_message = "number_of_workers must be at least 2 (Spark jobs need a driver and an executor)."
  }
}

variable "timeout_minutes" {
  description = "Hard stop of one job run."
  type        = number
  default     = 120
}

variable "extra_job_arguments" {
  description = "Extra --key = value arguments per job key (bronze, silver, gold, export-training, export-rds, export-monitor), e.g. Spark settings from the data engineers."
  type        = map(map(string))
  default     = {}
}

# ------------------------------------------------------------------ Network and database
variable "subnet_id" {
  description = "Private-app subnet of the Glue NETWORK connection (Glue places the job ENIs in one subnet)."
  type        = string
}

variable "availability_zone" {
  description = "Availability zone of subnet_id."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups of the job ENIs: glue (self-referencing) + data_clients (PostgreSQL to RDS Proxy)."
  type        = list(string)
}

variable "db_host" {
  description = "RDS Proxy endpoint (export-rds job)."
  type        = string
}

variable "db_name" {
  description = "Database name."
  type        = string
}

variable "db_user" {
  description = "Database user of the export-rds job (IAM token through RDS Proxy)."
  type        = string
  default     = "mmm_etl"
}

variable "db_user_arn" {
  description = "rds-db:connect ARN of db_user on the proxy."
  type        = string
}

# ------------------------------------------------------------------ Data quality
variable "silver_ruleset" {
  description = "Glue Data Quality ruleset (DQDL) the Silver job evaluates; failing rules stop the refresh. Owned by the data engineers (data/glue/dq/silver.dqdl)."
  type        = string
  default     = "Rules = [ RowCount > 0 ]"
}

# ------------------------------------------------------------------ Account settings
variable "manage_catalog_encryption" {
  description = "Set the account-level Data Catalog encryption (metadata and connection passwords with the s3 key). false if WBD already manages it."
  type        = bool
  default     = true
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the Glue job role."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

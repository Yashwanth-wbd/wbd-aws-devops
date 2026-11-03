variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev. The environment is <name_prefix>-airflow."
  type        = string
}

variable "airflow_version" {
  description = "MWAA Airflow version. data/requirements.txt must use the constraints file of the same version."
  type        = string
  default     = "2.10.3"
}

variable "environment_class" {
  description = "mw1.micro / mw1.small / mw1.medium / mw1.large / ..."
  type        = string
  default     = "mw1.small"
}

variable "min_workers" {
  description = "Minimum Celery workers."
  type        = number
  default     = 1
}

variable "max_workers" {
  description = "Maximum Celery workers (MWAA scales on queued tasks)."
  type        = number
  default     = 2
}

variable "schedulers" {
  description = "Number of schedulers (2 for availability; mw1.micro allows 1)."
  type        = number
  default     = 2
}

variable "source_bucket_arn" {
  description = "MWAA bucket (DAGs under dags/, requirements.txt at the root). Versioning must be on."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets; MWAA uses the first two (two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "MWAA needs two private subnets in different AZs."
  }
}

variable "security_group_id" {
  description = "Self-referencing MWAA security group (network module, mwaa)."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed key for the environment (metadata DB, logs, Celery queue). Its policy must allow CloudWatch Logs."
  type        = string
}

variable "secrets_prefix" {
  description = "Secrets Manager prefix for Airflow, e.g. mmm/dev/airflow (connections under <prefix>/connections/<conn_id>)."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "KMS key of the Secrets Manager secrets."
  type        = string
}

variable "data_bucket_arns" {
  description = "Buckets the DAG tasks read and write (landing, results, data-quality)."
  type        = list(string)
  default     = []
}

variable "data_kms_key_arns" {
  description = "Keys of those buckets: the s3 key, the per-business-unit keys and the S3 key of the MWAA bucket."
  type        = list(string)
}

variable "dag_settings" {
  description = "Non-secret settings for the DAGs, set as Airflow option mmm.<key> (conf.get(\"mmm\", key))."
  type        = map(string)
  default     = {}
}

variable "log_level" {
  description = "Log level of the scheduler, worker, webserver and DAG processing logs."
  type        = string
  default     = "WARNING"
}

variable "weekly_maintenance_window_start" {
  description = "MWAA maintenance window start (UTC), DAY:HH:MM."
  type        = string
  default     = "SUN:03:00"
}

variable "alarm_topic_arn" {
  description = "SNS topic for the scheduler-heartbeat alarm (monitoring module)."
  type        = string
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

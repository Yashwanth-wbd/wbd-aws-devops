variable "name_prefix" {
  description = "Resource name prefix, e.g. mmm-dev."
  type        = string
}

variable "environment" {
  description = "dev, staging or prod (passed to the DAG run conf)."
  type        = string
}

variable "landing_bucket_name" {
  description = "Landing bucket; it must send events to EventBridge (s3-bucket enable_eventbridge)."
  type        = string
}

variable "business_units" {
  description = "Only objects under <business_unit>/ start a run."
  type        = list(string)
}

variable "mwaa_environment_name" {
  description = "MWAA environment the runs start in."
  type        = string
}

variable "airflow_role_arn" {
  description = "Airflow role the Lambda may call the REST API as (mwaa module airflow_user_role_arn)."
  type        = string
}

variable "dag_id" {
  description = "DAG started for every trigger."
  type        = string
  default     = "mmm_ingest"
}

variable "ondemand_source" {
  description = "EventBridge source of on-demand requests (scripts/trigger-ondemand.sh)."
  type        = string
  default     = "mmm.ondemand"
}

variable "ondemand_detail_type" {
  description = "EventBridge detail-type of on-demand requests."
  type        = string
  default     = "Data refresh requested"
}

variable "subnet_ids" {
  description = "Private-app subnets (NAT route to the MWAA API)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group of the Lambda (network module, data_trigger)."
  type        = string
}

variable "reserved_concurrency" {
  description = "Maximum parallel Lambda executions (protects MWAA from bursts)."
  type        = number
  default     = 5
}

variable "lambda_kms_key_arn" {
  description = "Key for the Lambda environment variables."
  type        = string
}

variable "sqs_kms_key_arn" {
  description = "Key of the dead-letter queue (kms module, sqs)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Key of the Lambda log group (kms module, logs)."
  type        = string
}

variable "log_retention_days" {
  description = "Lambda log retention."
  type        = number
  default     = 30
}

variable "alarm_topic_arn" {
  description = "SNS topic for the error and dead-letter alarms."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Permission boundary of the Lambda role."
  type        = string
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}

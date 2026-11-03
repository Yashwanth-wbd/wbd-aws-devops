output "environment_name" {
  description = "MWAA environment name."
  value       = aws_mwaa_environment.this.name
}

output "environment_arn" {
  description = "MWAA environment ARN."
  value       = aws_mwaa_environment.this.arn
}

output "webserver_url" {
  description = "Private Airflow UI host name (reachable only from the VPC / WBD network)."
  value       = aws_mwaa_environment.this.webserver_url
}

output "execution_role_arn" {
  description = "MWAA execution role."
  value       = aws_iam_role.execution.arn
}

# airflow:InvokeRestApi is granted on an Airflow role of the environment (User can trigger DAG runs).
output "airflow_user_role_arn" {
  description = "Airflow User role ARN for airflow:InvokeRestApi."
  value       = "arn:${local.partition}:airflow:${local.region}:${local.account_id}:role/${local.name}/User"
}

output "log_group_names" {
  description = "CloudWatch log groups MWAA writes to, per log type."
  value = {
    scheduler = element(split(":log-group:", aws_mwaa_environment.this.logging_configuration[0].scheduler_logs[0].cloud_watch_log_group_arn), 1)
    task      = element(split(":log-group:", aws_mwaa_environment.this.logging_configuration[0].task_logs[0].cloud_watch_log_group_arn), 1)
    worker    = element(split(":log-group:", aws_mwaa_environment.this.logging_configuration[0].worker_logs[0].cloud_watch_log_group_arn), 1)
  }
}

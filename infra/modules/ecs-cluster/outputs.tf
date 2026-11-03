output "cluster_name" {
  description = "Cluster name - GitHub variable ECS_CLUSTER."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "execution_role_arn" {
  description = "Shared task execution role ARN."
  value       = aws_iam_role.exec.arn
}

output "service_connect_namespace_arn" {
  description = "Service Connect (Cloud Map HTTP) namespace ARN."
  value       = aws_service_discovery_http_namespace.this.arn
}

output "exec_kms_key_arn" {
  description = "KMS key that encrypts ECS Exec sessions (task roles need kms:Decrypt, engineers kms:GenerateDataKey)."
  value       = var.logs_kms_key_arn
}

output "exec_audit_log_group_name" {
  description = "ECS Exec audit log group name (shipped to Splunk)."
  value       = aws_cloudwatch_log_group.exec.name
}

output "exec_audit_log_group_arn" {
  description = "ECS Exec audit log group ARN (task roles need write access when ECS Exec is on)."
  value       = aws_cloudwatch_log_group.exec.arn
}

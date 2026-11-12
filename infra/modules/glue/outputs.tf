output "role_arn" {
  description = "Glue job role."
  value       = aws_iam_role.this.arn
}

output "job_names" {
  description = "Job name per key (bronze, silver, gold, export-training, export-rds, export-monitor)."
  value       = { for k, j in aws_glue_job.this : k => j.name }
}

output "job_arns" {
  description = "Job ARN per key."
  value       = { for k, j in aws_glue_job.this : k => j.arn }
}

output "database_names" {
  description = "Data Catalog database per layer (bronze, silver, gold)."
  value       = { for k, d in aws_glue_catalog_database.this : k => d.name }
}

output "connection_name" {
  description = "NETWORK connection of the jobs."
  value       = aws_glue_connection.vpc.name
}

output "ruleset_name" {
  description = "Silver Data Quality ruleset."
  value       = aws_glue_data_quality_ruleset.silver.name
}

output "log_group_name" {
  description = "Continuous log group of the jobs."
  value       = aws_cloudwatch_log_group.this.name
}

output "security_configuration" {
  description = "Security configuration of the jobs."
  value       = aws_glue_security_configuration.this.name
}

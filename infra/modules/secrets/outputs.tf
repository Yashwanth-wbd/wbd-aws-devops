output "secret_arns" {
  description = "Secret ARN per key (e.g. secret_arns[\"redis/token\"]); used in task definitions and execution-role policies."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_names" {
  description = "Full secret name per key."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}

output "generated_values" {
  description = "Values of the generated secrets, for resources that need them directly (ElastiCache auth token, CloudFront custom header)."
  value       = { for k, p in random_password.this : k => p.result }
  sensitive   = true
}

output "parameter_arns" {
  description = "SSM parameter ARN per key."
  value       = { for k, p in aws_ssm_parameter.this : k => p.arn }
}

output "parameter_names" {
  description = "Full SSM parameter name per key."
  value       = { for k, p in aws_ssm_parameter.this : k => p.name }
}

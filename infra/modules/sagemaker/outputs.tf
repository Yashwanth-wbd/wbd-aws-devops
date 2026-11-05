output "role_arn" {
  description = "Job execution role ARN (passed by Step Functions)."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Job execution role name."
  value       = aws_iam_role.this.name
}

output "model_package_group_names" {
  description = "Model package group per business unit."
  value       = { for k, g in aws_sagemaker_model_package_group.this : k => g.model_package_group_name }
}

output "model_package_group_arns" {
  description = "Model package group ARNs per business unit."
  value       = { for k, g in aws_sagemaker_model_package_group.this : k => g.arn }
}

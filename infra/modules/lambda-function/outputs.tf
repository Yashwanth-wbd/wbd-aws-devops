output "function_name" {
  description = "Function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Function ARN (unqualified)."
  value       = aws_lambda_function.this.arn
}

output "alias_arn" {
  description = "ARN of the live alias - what callers invoke."
  value       = aws_lambda_alias.live.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the live alias (API Gateway integrations)."
  value       = aws_lambda_alias.live.invoke_arn
}

output "role_arn" {
  description = "Function role ARN."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Function log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "alarm_name" {
  description = "Errors alarm."
  value       = aws_cloudwatch_metric_alarm.errors.alarm_name
}

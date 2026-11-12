output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Lambda function ARN (invoked by the model-refresh and model-monitor state machines)."
  value       = aws_lambda_function.this.arn
}

output "log_group_name" {
  description = "Lambda log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "alarm_name" {
  description = "Errors alarm."
  value       = aws_cloudwatch_metric_alarm.errors.alarm_name
}

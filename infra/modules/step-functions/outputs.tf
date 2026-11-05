output "state_machine_arn" {
  description = "State machine ARN."
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "State machine name."
  value       = aws_sfn_state_machine.this.name
}

output "role_arn" {
  description = "State machine role ARN."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Execution log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "alarm_name" {
  description = "Failed-execution alarm."
  value       = aws_cloudwatch_metric_alarm.failed.alarm_name
}

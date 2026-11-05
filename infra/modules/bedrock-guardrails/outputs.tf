output "guardrail_id" {
  description = "Guardrail ID."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "Guardrail ARN."
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  description = "Pinned guardrail version."
  value       = aws_bedrock_guardrail_version.this.version
}

output "alarm_name" {
  description = "Interventions alarm."
  value       = aws_cloudwatch_metric_alarm.interventions.alarm_name
}

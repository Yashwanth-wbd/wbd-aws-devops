output "guardrail_id" {
  description = "Guardrail ID (passed as guardrailIdentifier on every call)."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "Guardrail ARN (task role ApplyGuardrail)."
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  description = "Published guardrail version the gateway pins."
  value       = aws_bedrock_guardrail_version.this.version
}

output "model_arns" {
  description = "ARNs the approved model IDs resolve to (foundation models and inference profiles)."
  value       = local.model_arns
}

output "vpc_endpoint_id" {
  description = "bedrock-runtime interface endpoint (task role denies calls that do not come through it)."
  value       = aws_vpc_endpoint.bedrock_runtime.id
}

output "invocation_log_bucket" {
  description = "Bucket with the full invocation logs (null when logging is managed elsewhere)."
  value       = var.enable_invocation_logging ? module.invocation_bucket[0].bucket_name : null
}

output "invocation_log_group" {
  description = "Log group with the invocation logs (null when logging is managed elsewhere)."
  value       = var.enable_invocation_logging ? aws_cloudwatch_log_group.invocations[0].name : null
}

output "dashboard_name" {
  description = "GenAI CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.genai.dashboard_name
}

output "alarm_names" {
  description = "GenAI alarm names."
  value = concat(
    [for a in aws_cloudwatch_metric_alarm.model : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.daily_tokens_total : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.daily_tokens_bu : a.alarm_name],
  )
}

output "budget_name" {
  description = "GenAI cost budget."
  value       = aws_budgets_budget.genai.name
}

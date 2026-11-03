output "function_name" {
  description = "Data-trigger Lambda name."
  value       = aws_lambda_function.this.function_name
}

output "log_group_name" {
  description = "Lambda log group (each event logs started / duplicate / ignored with the dag_run_id)."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "dlq_url" {
  description = "Dead-letter queue of events that could not start a run."
  value       = aws_sqs_queue.dlq.id
}

output "rule_names" {
  description = "EventBridge rule names (landing, ondemand)."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.name }
}

output "ondemand_event" {
  description = "Source and detail-type of on-demand requests."
  value       = { source = var.ondemand_source, detail_type = var.ondemand_detail_type }
}

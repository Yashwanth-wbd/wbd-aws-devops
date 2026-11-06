output "queue_url" {
  description = "URL of the run queue (API env OPTIMIZATION_QUEUE_URL)."
  value       = aws_sqs_queue.this.id
}

output "queue_arn" {
  description = "ARN of the run queue."
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "Name of the run queue."
  value       = aws_sqs_queue.this.name
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue (redrive source)."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Name of the dead-letter queue."
  value       = aws_sqs_queue.dlq.name
}

output "dispatcher_function_name" {
  description = "Name of the dispatcher Lambda."
  value       = aws_lambda_function.dispatcher.function_name
}

output "log_group_name" {
  description = "Log group of the dispatcher."
  value       = aws_cloudwatch_log_group.dispatcher.name
}

output "alarm_names" {
  description = "Alarms created by the module."
  value       = [for a in aws_cloudwatch_metric_alarm.this : a.alarm_name]
}

output "queue_url" {
  description = "Job queue URL - OPTIMIZE_QUEUE_URL in the task definitions."
  value       = aws_sqs_queue.jobs.id
}

output "queue_arn" {
  description = "Job queue ARN."
  value       = aws_sqs_queue.jobs.arn
}

output "queue_name" {
  description = "Job queue name (used by autoscaling and alarms)."
  value       = aws_sqs_queue.jobs.name
}

output "dlq_url" {
  description = "Dead-letter queue URL."
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "Dead-letter queue ARN."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "Dead-letter queue name (DLQ depth alarm in Step 9)."
  value       = aws_sqs_queue.dlq.name
}

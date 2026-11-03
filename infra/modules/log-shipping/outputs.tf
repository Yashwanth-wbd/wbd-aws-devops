output "delivery_stream_name" {
  description = "Firehose stream name (null while disabled)."
  value       = one(aws_kinesis_firehose_delivery_stream.splunk[*].name)
}

output "delivery_stream_arn" {
  description = "Firehose stream ARN (null while disabled)."
  value       = one(aws_kinesis_firehose_delivery_stream.splunk[*].arn)
}

output "shipped_log_groups" {
  description = "Log groups with a Splunk subscription filter."
  value       = [for f in aws_cloudwatch_log_subscription_filter.splunk : f.log_group_name]
}

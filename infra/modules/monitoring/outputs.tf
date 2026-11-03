output "alert_topic_arn" {
  description = "SNS alert topic (alarms in other modules, e.g. log-shipping, publish here)."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "All alarm names of this module."
  value       = concat([for a in aws_cloudwatch_metric_alarm.simple : a.alarm_name], [aws_cloudwatch_metric_alarm.api_5xx_rate.alarm_name, aws_cloudwatch_metric_alarm.whatif_latency.alarm_name])
}

output "event_rule_names" {
  description = "EventBridge alert rules."
  value       = [for r in aws_cloudwatch_event_rule.alert : r.name]
}

output "dashboard_name" {
  description = "CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.platform.dashboard_name
}

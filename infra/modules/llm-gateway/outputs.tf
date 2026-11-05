output "invoke_url" {
  description = "Base URL the API calls (SigV4, service execute-api): <url>/<provider>/<provider path>."
  value       = "https://${aws_api_gateway_rest_api.this.id}-${var.vpc_endpoint_id}.execute-api.${local.region}.amazonaws.com/${aws_api_gateway_stage.v1.stage_name}"
}

output "rest_api_id" {
  description = "REST API ID."
  value       = aws_api_gateway_rest_api.this.id
}

output "execution_arn" {
  description = "Execution ARN (for execute-api:Invoke policies)."
  value       = "${aws_api_gateway_rest_api.this.execution_arn}/${aws_api_gateway_stage.v1.stage_name}/*/*"
}

output "proxy_function_name" {
  description = "Proxy Lambda name."
  value       = aws_lambda_function.proxy.function_name
}

output "log_group_names" {
  description = "Proxy and access log groups."
  value       = { proxy = aws_cloudwatch_log_group.proxy.name, access = aws_cloudwatch_log_group.access.name }
}

output "alarm_names" {
  description = "Gateway alarms."
  value       = [aws_cloudwatch_metric_alarm.errors_5xx.alarm_name]
}

output "web_acl_arn" {
  description = "Web ACL ARN."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_name" {
  description = "Web ACL name (CloudWatch WebACL dimension)."
  value       = aws_wafv2_web_acl.this.name
}

output "log_group_name" {
  description = "WAF log group (shipped to Splunk when enabled)."
  value       = aws_cloudwatch_log_group.this.name
}

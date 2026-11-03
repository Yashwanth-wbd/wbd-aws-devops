output "distribution_id" {
  description = "CloudFront distribution ID (GitHub variable CLOUDFRONT_DISTRIBUTION_ID)."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "Distribution ARN (frontend bucket policy condition)."
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "dxxxx.cloudfront.net - target of the CNAME for every alias."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront hosted zone ID (for Route 53 alias records later)."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "app_url" {
  description = "https URL of the app (first alias) - GitHub variable APP_URL and Okta redirect base."
  value       = "https://${var.aliases[0]}"
}

output "web_acl_arn" {
  description = "WAF web ACL ARN."
  value       = aws_wafv2_web_acl.this.arn
}

output "waf_log_group_name" {
  description = "WAF log group in us-east-1."
  value       = aws_cloudwatch_log_group.waf.name
}

output "frontend_kvs_arn" {
  description = "Key value store holding current_release (frontend-ci.yml writes it)."
  value       = aws_cloudfront_key_value_store.frontend.arn
}

output "frontend_function_name" {
  description = "Viewer-request router function."
  value       = aws_cloudfront_function.frontend_router.name
}

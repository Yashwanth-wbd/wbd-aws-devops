output "bucket_name" {
  description = "Log bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Log bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Bucket domain name (CloudFront logging config needs this form)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "prefixes" {
  description = "Prefix per log producer: alb, cloudfront, s3_access."
  value       = local.prefixes
}

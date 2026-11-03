output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch metric dimension)."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name. The origin hostname in the certificate must point (CNAME) here."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (Route 53 alias)."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "API target group ARN."
  value       = aws_lb_target_group.api.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch metric dimension)."
  value       = aws_lb_target_group.api.arn_suffix
}

output "https_listener_arn" {
  description = "HTTPS listener ARN."
  value       = aws_lb_listener.https.arn
}

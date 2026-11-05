output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch metric dimension)."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name. The app host name must point (alias / CNAME) here."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (Route 53 alias)."
  value       = aws_lb.this.zone_id
}

output "target_group_arns" {
  description = "Target group ARN per service (ui, api)."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "target_group_arn_suffixes" {
  description = "Target group ARN suffix per service (CloudWatch metric dimension)."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}

output "https_listener_arn" {
  description = "HTTPS listener ARN."
  value       = aws_lb_listener.https.arn
}

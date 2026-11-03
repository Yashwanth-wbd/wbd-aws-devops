output "registry" {
  description = "Registry host (<account>.dkr.ecr.<region>.amazonaws.com) - GitHub variable ECR_REGISTRY."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "repository_urls" {
  description = "Repository URL per name."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Repository ARN per name."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

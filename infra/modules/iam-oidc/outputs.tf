output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = local.oidc_provider_arn
}

output "role_arns" {
  description = "Pipeline role ARNs: plan, apply, deploy, ecr_push, (dev/staging) ecr_read and (data platform) model_eval, model_approve."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "trusted_subjects" {
  description = "GitHub OIDC subjects each role trusts (for review)."
  value       = { for k, _ in local.created_roles : k => local.subjects[k] }
}

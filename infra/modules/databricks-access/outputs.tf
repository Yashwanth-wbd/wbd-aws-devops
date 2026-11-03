output "uc_role_arn" {
  description = "IAM role WBD registers as the Unity Catalog storage credential."
  value       = aws_iam_role.uc.arn
}

output "uc_external_id" {
  description = "External ID the Databricks storage credential uses (the Databricks account ID)."
  value       = var.databricks_account_id
}

output "workspace_endpoint_id" {
  description = "PrivateLink endpoint ID (null when disabled). WBD registers it in the Databricks account console."
  value       = one(aws_vpc_endpoint.workspace[*].id)
}

output "private_zone_id" {
  description = "Private hosted zone of the workspace host name (null when disabled)."
  value       = one(aws_route53_zone.workspace[*].zone_id)
}

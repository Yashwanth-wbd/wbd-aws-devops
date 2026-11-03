output "vault_name" {
  description = "Backup vault in the stack's region."
  value       = aws_backup_vault.this.name
}

output "vault_arn" {
  description = "Backup vault ARN."
  value       = aws_backup_vault.this.arn
}

output "dr_vault_arn" {
  description = "DR-region vault ARN (null without cross-region copy)."
  value       = one(aws_backup_vault.dr[*].arn)
}

output "plan_id" {
  description = "Backup plan ID (start an on-demand job: aws backup start-backup-job)."
  value       = aws_backup_plan.this.id
}

output "backup_role_arn" {
  description = "Role AWS Backup uses for backups and restores."
  value       = aws_iam_role.backup.arn
}

output "selection_tag" {
  description = "Tag key that selects resources (value \"true\")."
  value       = var.selection_tag
}

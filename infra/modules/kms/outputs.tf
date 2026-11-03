output "key_arns" {
  description = "KMS key ARN per purpose."
  value       = { for p, k in aws_kms_key.this : p => k.arn }
}

output "key_ids" {
  description = "KMS key ID per purpose."
  value       = { for p, k in aws_kms_key.this : p => k.key_id }
}

output "alias_names" {
  description = "KMS alias name per purpose."
  value       = { for p, a in aws_kms_alias.this : p => a.name }
}

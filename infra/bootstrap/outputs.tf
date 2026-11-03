output "state_bucket_name" {
  description = "S3 bucket holding Terraform state for this account."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  description = "KMS key that encrypts the state bucket."
  value       = aws_kms_key.state.arn
}

output "lock_table_name" {
  description = "DynamoDB lock table name, or null when S3 lock files are used."
  value       = var.enable_dynamodb_lock ? aws_dynamodb_table.lock[0].name : null
}

output "backend_config" {
  description = "Values for infra/environments/<env>/backend.tf (Step 3)."
  value = {
    bucket       = aws_s3_bucket.state.bucket
    region       = var.aws_region
    encrypt      = true
    kms_key_id   = aws_kms_key.state.arn
    use_lockfile = true
  }
}

output "caller_account_id" {
  description = "Account the bootstrap ran in (sanity check)."
  value       = data.aws_caller_identity.current.account_id
}

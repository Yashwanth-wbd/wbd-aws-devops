locals {
  tags = merge(var.tags, { Component = "secrets" })

  generated = { for k, s in var.secrets : k => s if s.generate }
}

# ------------------------------------------------------------------ Secrets Manager
resource "aws_secretsmanager_secret" "this" {
  #checkov:skip=CKV2_AWS_57:Generated secrets rotate via generated_secret_rotation_id; external tokens rotate when the issuer rotates them (docs/05-secrets-and-config.md).
  for_each = var.secrets

  name                    = "${var.path_prefix}/${each.key}"
  description             = each.value.description
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.tags, {
    Name     = "${var.path_prefix}/${each.key}"
    FilledBy = each.value.generate ? "terraform" : "devops-out-of-band"
  })
}

# Alphanumeric only: valid in a PostgreSQL connection string and as an HTTP header value.
resource "random_password" "this" {
  for_each = local.generated

  length  = each.value.length
  special = false

  keepers = {
    rotation_id = var.generated_secret_rotation_id
  }
}

resource "aws_secretsmanager_secret_version" "generated" {
  for_each = local.generated

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = random_password.this[each.key].result
}

# ------------------------------------------------------------------ SSM Parameter Store
resource "aws_ssm_parameter" "this" {
  #checkov:skip=CKV2_AWS_34:Only non-secret settings are String; anything sensitive uses secure = true (SecureString with the secrets key).
  for_each = var.parameters

  name        = "/${var.path_prefix}/${each.key}"
  description = each.value.description
  type        = each.value.secure ? "SecureString" : "String"
  key_id      = each.value.secure ? var.kms_key_arn : null
  value       = each.value.value
  tier        = "Standard"

  tags = merge(local.tags, { Name = "/${var.path_prefix}/${each.key}" })
}

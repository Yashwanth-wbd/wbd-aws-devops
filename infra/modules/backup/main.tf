data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  tags       = merge(var.tags, { Component = "backup" })
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

# ------------------------------------------------------------------ Vault keys (separate from the data keys)
data "aws_iam_policy_document" "vault_key" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_111:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_356:Key policy; "*" means this key only and IAM policies then decide who can use it.
  statement {
    sid       = "EnableIAMPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "vault" {
  description             = "${var.name_prefix} AWS Backup vault encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.vault_key.json

  tags = merge(local.tags, { Name = "${var.name_prefix}-backup" })
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.name_prefix}-backup"
  target_key_id = aws_kms_key.vault.key_id
}

resource "aws_kms_key" "dr_vault" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  description             = "${var.name_prefix} AWS Backup DR vault encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.vault_key.json

  tags = merge(local.tags, { Name = "${var.name_prefix}-backup-dr" })
}

resource "aws_kms_alias" "dr_vault" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  name          = "alias/${var.name_prefix}-backup-dr"
  target_key_id = aws_kms_key.dr_vault[0].key_id
}

# ------------------------------------------------------------------ Vaults
resource "aws_backup_vault" "this" {
  name        = "${var.name_prefix}-vault"
  kms_key_arn = aws_kms_key.vault.arn

  tags = local.tags
}

resource "aws_backup_vault" "dr" {
  count    = var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  name        = "${var.name_prefix}-vault-dr"
  kms_key_arn = aws_kms_key.dr_vault[0].arn

  tags = local.tags
}

# Nobody may delete recovery points or shorten their life by hand; only expiry removes them.
data "aws_iam_policy_document" "vault_access" {
  statement {
    sid       = "DenyManualDeletion"
    effect    = "Deny"
    actions   = ["backup:DeleteRecoveryPoint", "backup:UpdateRecoveryPointLifecycle"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_backup_vault_policy" "this" {
  count = var.deny_manual_deletion ? 1 : 0

  backup_vault_name = aws_backup_vault.this.name
  policy            = data.aws_iam_policy_document.vault_access.json
}

resource "aws_backup_vault_policy" "dr" {
  count    = var.enable_cross_region_copy && var.deny_manual_deletion ? 1 : 0
  provider = aws.dr

  backup_vault_name = aws_backup_vault.dr[0].name
  policy            = data.aws_iam_policy_document.vault_access.json
}

resource "aws_backup_vault_lock_configuration" "this" {
  count = var.vault_lock == null ? 0 : 1

  backup_vault_name   = aws_backup_vault.this.name
  min_retention_days  = var.vault_lock.min_retention_days
  max_retention_days  = var.vault_lock.max_retention_days
  changeable_for_days = var.vault_lock.changeable_for_days
}

resource "aws_backup_vault_lock_configuration" "dr" {
  count    = var.vault_lock != null && var.enable_cross_region_copy ? 1 : 0
  provider = aws.dr

  backup_vault_name   = aws_backup_vault.dr[0].name
  min_retention_days  = var.vault_lock.min_retention_days
  max_retention_days  = var.vault_lock.max_retention_days
  changeable_for_days = var.vault_lock.changeable_for_days
}

# ------------------------------------------------------------------ Backup role
data "aws_iam_policy_document" "backup_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name                 = "${var.name_prefix}-backup"
  assume_role_policy   = data.aws_iam_policy_document.backup_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "service-role/AWSBackupServiceRolePolicyForBackup",
    "service-role/AWSBackupServiceRolePolicyForRestores",
    "AWSBackupServiceRolePolicyForS3Backup",
    "AWSBackupServiceRolePolicyForS3Restore",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# ------------------------------------------------------------------ Plan and selection
resource "aws_backup_plan" "this" {
  name = "${var.name_prefix}-daily"

  rule {
    rule_name                    = "daily"
    target_vault_name            = aws_backup_vault.this.name
    schedule                     = var.schedule
    schedule_expression_timezone = "Etc/UTC"
    start_window                 = 60
    completion_window            = 360
    recovery_point_tags          = merge(local.tags, { BackupRule = "daily" })

    lifecycle {
      delete_after = var.daily_retention_days
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_copy ? [1] : []

      content {
        destination_vault_arn = aws_backup_vault.dr[0].arn

        lifecycle {
          delete_after = var.dr_retention_days
        }
      }
    }
  }

  dynamic "rule" {
    for_each = var.monthly_retention_days == null ? [] : [1]

    content {
      rule_name                    = "monthly"
      target_vault_name            = aws_backup_vault.this.name
      schedule                     = "cron(0 5 1 * ? *)"
      schedule_expression_timezone = "Etc/UTC"
      start_window                 = 60
      completion_window            = 720
      recovery_point_tags          = merge(local.tags, { BackupRule = "monthly" })

      lifecycle {
        delete_after = var.monthly_retention_days
      }
    }
  }

  tags = local.tags
}

resource "aws_backup_selection" "tagged" {
  name         = "${var.name_prefix}-tag-${var.selection_tag}"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = ["*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/${var.selection_tag}"
      value = "true"
    }
  }
}

# ------------------------------------------------------------------ Alerts on failed jobs
resource "aws_cloudwatch_event_rule" "job_failed" {
  name        = "${var.name_prefix}-backup-job-failed"
  description = "AWS Backup backup, copy or restore job failed, aborted or expired"
  event_pattern = jsonencode({
    source        = ["aws.backup"]
    "detail-type" = ["Backup Job State Change", "Copy Job State Change", "Restore Job State Change"]
    detail        = { state = ["FAILED", "ABORTED", "EXPIRED"] }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "job_failed" {
  rule      = aws_cloudwatch_event_rule.job_failed.name
  target_id = "sns"
  arn       = var.alert_topic_arn

  input_transformer {
    input_paths = {
      type     = "$.detail-type"
      state    = "$.detail.state"
      resource = "$.detail.resourceArn"
      reason   = "$.detail.statusMessage"
    }
    input_template = "\"AWS Backup <type>: <state> for <resource>. <reason>\""
  }
}

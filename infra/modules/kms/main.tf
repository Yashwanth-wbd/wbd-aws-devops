data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
}

data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_111:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_356:Key policy; "*" means this key only and IAM policies then decide who can use it.
  for_each = toset(var.purposes)

  source_policy_documents = compact([lookup(var.additional_policy_documents, each.key, "")])

  statement {
    sid       = "EnableIAMPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # CloudWatch Logs cannot use IAM grants, so log-group encryption needs the service in the key policy.
  dynamic "statement" {
    for_each = contains(var.logs_service_purposes, each.key) ? [1] : []

    content {
      sid       = "AllowCloudWatchLogsInThisAccount"
      actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["logs.${local.region}.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  for_each = toset(var.purposes)

  description             = "${var.name_prefix} ${each.key} encryption"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key[each.key].json

  tags = merge(var.tags, {
    Name      = "${var.name_prefix}-${each.key}"
    Component = "kms"
  })
}

resource "aws_kms_alias" "this" {
  for_each = toset(var.purposes)

  name          = "alias/${var.name_prefix}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}

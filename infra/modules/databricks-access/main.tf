data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  uc_role_name   = "${var.name_prefix}-databricks-uc"
  uc_role_arn    = "arn:${local.partition}:iam::${local.account_id}:role/${local.uc_role_name}"
  workspace_name = trimsuffix(replace(var.workspace_host, "https://", ""), "/")

  tags = merge(var.tags, { Component = "data-platform" })
}

# ------------------------------------------------------------------ Unity Catalog storage-credential role
# Phase 1: only the Databricks UC master role may assume it (external ID = Databricks account ID).
# Phase 2 (after WBD registers the storage credential): self_assume_enabled = true adds the
# self-assume statement Databricks requires. The role must exist before it can trust itself.
data "aws_iam_policy_document" "uc_trust" {
  statement {
    sid     = "DatabricksUnityCatalog"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.self_assume_enabled ? [var.uc_master_role_arn, local.uc_role_arn] : [var.uc_master_role_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}

resource "aws_iam_role" "uc" {
  name                 = local.uc_role_name
  description          = "Unity Catalog storage credential for ${var.name_prefix} buckets"
  assume_role_policy   = data.aws_iam_policy_document.uc_trust.json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600

  tags = local.tags
}

data "aws_iam_policy_document" "uc" {
  statement {
    sid = "Buckets"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
      "s3:GetBucketLocation", "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration",
    ]
    resources = concat(var.bucket_arns, [for b in var.bucket_arns : "${b}/*"])
  }

  statement {
    sid       = "BucketKeys"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*"]
    resources = var.kms_key_arns
  }

  statement {
    sid       = "SelfAssume"
    actions   = ["sts:AssumeRole"]
    resources = [local.uc_role_arn]
  }
}

resource "aws_iam_role_policy" "uc" {
  name   = "unity-catalog"
  role   = aws_iam_role.uc.id
  policy = data.aws_iam_policy_document.uc.json
}

# ------------------------------------------------------------------ PrivateLink to the workspace (front-end / REST API)
resource "aws_vpc_endpoint" "workspace" {
  count = var.enable_privatelink ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = var.workspace_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.endpoint_subnet_ids
  security_group_ids  = [var.endpoint_security_group_id]
  private_dns_enabled = false

  tags = merge(local.tags, { Name = "${var.name_prefix}-databricks-workspace" })

  lifecycle {
    precondition {
      condition     = var.workspace_service_name != null
      error_message = "enable_privatelink needs workspace_service_name (databricks_privatelink_service_name from WBD Databricks)."
    }
  }
}

# The workspace host name resolves to the endpoint inside the VPC (tasks in the VPC).
resource "aws_route53_zone" "workspace" {
  #checkov:skip=CKV2_AWS_38:DNSSEC signing applies to public zones; this zone is private.
  #checkov:skip=CKV2_AWS_39:Query logging for this one-record private zone is not required by WBD (VPC flow logs cover it).
  count = var.enable_privatelink ? 1 : 0

  name    = local.workspace_name
  comment = "Databricks workspace over PrivateLink (${var.name_prefix})"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = local.tags
}

resource "aws_route53_record" "workspace" {
  count = var.enable_privatelink ? 1 : 0

  zone_id = aws_route53_zone.workspace[0].zone_id
  name    = local.workspace_name
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.workspace[0].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.workspace[0].dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

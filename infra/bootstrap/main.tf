locals {
  env_short = {
    dev     = "dev"
    staging = "stg"
    prod    = "prd"
  }[var.environment]

  # us-east-1 -> use1, eu-west-1 -> euw1
  region_parts = split("-", var.aws_region)
  region_code  = "${local.region_parts[0]}${substr(local.region_parts[1], 0, 1)}${local.region_parts[2]}"

  name_prefix       = "mmm-${local.env_short}"
  state_bucket_name = "wbd-mmm-${local.env_short}-tfstate-${local.region_code}"
  lock_table_name   = "${local.name_prefix}-tfstate-lock"

  tags = {
    Application        = "mmm-media-allocation"
    Environment        = local.env_short
    Owner              = var.owner
    CostCenter         = var.cost_center
    BusinessUnit       = "shared"
    DataClassification = var.data_classification
    ManagedBy          = "terraform"
    Component          = "tfstate"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ------------------------------------------------------------------ KMS key for state
data "aws_iam_policy_document" "state_kms" {
  #checkov:skip=CKV_AWS_109:Standard KMS default key policy; in a key policy "*" means this key only, access is then granted by IAM.
  #checkov:skip=CKV_AWS_111:Standard KMS default key policy; in a key policy "*" means this key only, access is then granted by IAM.
  #checkov:skip=CKV_AWS_356:Standard KMS default key policy; in a key policy "*" means this key only, access is then granted by IAM.
  statement {
    sid       = "EnableIAMPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.aws_account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "${local.name_prefix} Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.state_kms.json

  lifecycle {
    precondition {
      condition     = terraform.workspace == var.environment
      error_message = "Select the workspace that matches the tfvars: terraform workspace select ${var.environment}"
    }
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${local.name_prefix}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# ------------------------------------------------------------------ S3 state bucket
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logs go to the logs bucket, which is created in Step 6; enable then.
  #checkov:skip=CKV_AWS_144:Cross-region replication of state is added in prod only if WBD approves a DR region.
  #checkov:skip=CKV2_AWS_62:State bucket does not need event notifications.
  bucket = local.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyOldTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ------------------------------------------------------------------ Optional DynamoDB lock table
resource "aws_dynamodb_table" "lock" {
  count = var.enable_dynamodb_lock ? 1 : 0

  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  deletion_protection_enabled = true
}

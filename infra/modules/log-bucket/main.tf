data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_elb_service_account" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = merge(var.tags, { Component = "logs" })

  # Prefixes used by the log producers
  prefixes = {
    alb        = "alb"
    s3_access  = "s3-access"
    cloudtrail = "cloudtrail"
  }
}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:This is the access-log target itself; logging it to itself would loop.
  #checkov:skip=CKV_AWS_144:Logs are not replicated cross-region; Splunk holds the long-term copy.
  #checkov:skip=CKV_AWS_145:ALB access logs support only SSE-S3, so this bucket cannot use KMS.
  #checkov:skip=CKV2_AWS_62:No event notifications needed for log delivery.
  bucket        = var.bucket_name
  force_destroy = false

  tags = merge(local.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

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
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

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

  # ALB access logs: regions older than Aug 2022 use the regional ELB account, newer ones the service principal.
  statement {
    sid       = "AlbLogDeliveryElbAccount"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/${local.prefixes.alb}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.current.arn]
    }
  }

  statement {
    sid       = "AlbLogDeliveryService"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/${local.prefixes.alb}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "S3ServerAccessLogs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/${local.prefixes.s3_access}/*"]

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:s3:::*"]
    }
  }

  dynamic "statement" {
    for_each = var.cloudtrail_trail_arn == null ? [] : [1]
    content {
      sid       = "CloudTrailAclCheck"
      actions   = ["s3:GetBucketAcl"]
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [var.cloudtrail_trail_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.cloudtrail_trail_arn == null ? [] : [1]
    content {
      sid       = "CloudTrailDelivery"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/${local.prefixes.cloudtrail}/AWSLogs/${local.account_id}/*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = [var.cloudtrail_trail_arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

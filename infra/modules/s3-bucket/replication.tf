data "aws_region" "current" {}

data "aws_iam_policy_document" "replication_assume" {
  count = var.replication == null ? 0 : 1

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count = var.replication == null ? 0 : 1

  name                 = "${var.bucket_name}-replication"
  assume_role_policy   = data.aws_iam_policy_document.replication_assume[0].json
  permissions_boundary = var.replication.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "replication" {
  count = var.replication == null ? 0 : 1

  statement {
    sid       = "ReadSourceConfig"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "ReadSourceObjects"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
      "s3:GetObjectRetention",
      "s3:GetObjectLegalHold",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "WriteDestination"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags", "s3:ObjectOwnerOverrideToBucketOwner"]
    resources = ["${var.replication.destination_bucket_arn}/*"]
  }

  statement {
    sid       = "DecryptSource"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  statement {
    sid       = "EncryptDestination"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.replication.destination_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "replication" {
  count = var.replication == null ? 0 : 1

  name   = "replicate-to-dr"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.replication == null ? 0 : 1

  bucket = aws_s3_bucket.this.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-to-dr"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = var.replication.destination_bucket_arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = var.replication.destination_kms_key_arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# ------------------------------------------------------------------ Model invocation logging
# Full prompts and answers (audit trail) go to an encrypted bucket and log group in this account.
# The setting is one per account and region: turn enable_invocation_logging off if WBD already
# configures it centrally (docs/01 tracker).
data "aws_iam_policy_document" "invocation_bucket" {
  statement {
    sid       = "BedrockWritesInvocationLogs"
    actions   = ["s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::${var.invocation_log_bucket_name}/${var.invocation_log_prefix}/*"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_source_arn]
    }
  }
}

module "invocation_bucket" {
  source = "../s3-bucket"
  count  = var.enable_invocation_logging ? 1 : 0

  bucket_name            = var.invocation_log_bucket_name
  kms_key_arn            = var.kms_key_arn
  access_log_bucket      = var.access_log_bucket
  access_log_prefix      = var.access_log_prefix
  expiration_days        = var.invocation_log_s3_days
  additional_policy_json = data.aws_iam_policy_document.invocation_bucket.json
  component              = "genai"
  tags                   = var.tags
}

resource "aws_cloudwatch_log_group" "invocations" {
  #checkov:skip=CKV_AWS_338:Retention is set per environment (prod 365 days); the full record is kept in the S3 bucket (invocation_log_s3_days).
  count = var.enable_invocation_logging ? 1 : 0

  name              = "/aws/bedrock/${var.name_prefix}-invocations"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = local.tags
}

data "aws_iam_policy_document" "logging_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_source_arn]
    }
  }
}

resource "aws_iam_role" "logging" {
  count = var.enable_invocation_logging ? 1 : 0

  name                 = "${var.name_prefix}-bedrock-logging"
  assume_role_policy   = data.aws_iam_policy_document.logging_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "logging" {
  count = var.enable_invocation_logging ? 1 : 0

  statement {
    sid       = "WriteInvocationLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.invocations[0].arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "logging" {
  count = var.enable_invocation_logging ? 1 : 0

  name   = "invocation-logs"
  role   = aws_iam_role.logging[0].id
  policy = data.aws_iam_policy_document.logging[0].json
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.enable_invocation_logging ? 1 : 0

  logging_config {
    text_data_delivery_enabled      = true
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = false

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.invocations[0].name
      role_arn       = aws_iam_role.logging[0].arn
    }

    s3_config {
      bucket_name = module.invocation_bucket[0].bucket_name
      key_prefix  = var.invocation_log_prefix
    }
  }

  depends_on = [aws_iam_role_policy.logging]
}

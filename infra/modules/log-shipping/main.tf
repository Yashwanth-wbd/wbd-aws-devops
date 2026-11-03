data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  tags        = merge(var.tags, { Component = "log-shipping" })
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  region      = data.aws_region.current.name
  stream_name = "${var.name_prefix}-splunk"
  n           = var.enabled ? 1 : 0
}

# ------------------------------------------------------------------ Firehose role
data "aws_iam_policy_document" "firehose_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "firehose" {
  statement {
    sid       = "FailedRecordsToS3"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
    resources = [var.failed_records_bucket_arn, "${var.failed_records_bucket_arn}/${var.failed_records_prefix}/*"]
  }

  statement {
    sid       = "ReadHecToken"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.hec_secret_arn]
  }

  statement {
    sid       = "DecryptHecToken"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "EncryptFailedRecords"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.logs_kms_key_arn]
  }

  statement {
    sid       = "DeliveryErrorLogs"
    actions   = ["logs:PutLogEvents"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/kinesisfirehose/${local.stream_name}:*"]
  }
}

resource "aws_iam_role" "firehose" {
  count = local.n

  name                 = "${var.name_prefix}-firehose-splunk"
  assume_role_policy   = data.aws_iam_policy_document.firehose_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy" "firehose" {
  count = local.n

  name   = "firehose-splunk"
  role   = aws_iam_role.firehose[0].id
  policy = data.aws_iam_policy_document.firehose.json
}

# ------------------------------------------------------------------ Firehose stream
resource "aws_cloudwatch_log_group" "firehose" {
  count = local.n

  name              = "/aws/kinesisfirehose/${local.stream_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

resource "aws_cloudwatch_log_stream" "firehose" {
  count = local.n

  name           = "DestinationDelivery"
  log_group_name = aws_cloudwatch_log_group.firehose[0].name
}

resource "aws_kinesis_firehose_delivery_stream" "splunk" {
  count = local.n

  name        = local.stream_name
  destination = "splunk"

  server_side_encryption {
    enabled  = true
    key_type = "CUSTOMER_MANAGED_CMK"
    key_arn  = var.logs_kms_key_arn
  }

  splunk_configuration {
    hec_endpoint               = var.hec_endpoint
    hec_endpoint_type          = var.hec_endpoint_type
    hec_acknowledgment_timeout = 180
    retry_duration             = 300
    buffering_interval         = 60
    buffering_size             = 5
    s3_backup_mode             = "FailedEventsOnly"

    secrets_manager_configuration {
      enabled    = true
      secret_arn = var.hec_secret_arn
      role_arn   = aws_iam_role.firehose[0].arn
    }

    s3_configuration {
      role_arn            = aws_iam_role.firehose[0].arn
      bucket_arn          = var.failed_records_bucket_arn
      prefix              = "${var.failed_records_prefix}/"
      error_output_prefix = "${var.failed_records_prefix}-errors/!{firehose:error-output-type}/"
      compression_format  = "GZIP"
      kms_key_arn         = var.logs_kms_key_arn
    }

    # CloudWatch Logs subscription records arrive gzip-compressed; Splunk needs plain JSON.
    processing_configuration {
      enabled = true

      processors {
        type = "Decompression"

        parameters {
          parameter_name  = "CompressionFormat"
          parameter_value = "GZIP"
        }
      }

      dynamic "processors" {
        for_each = var.extract_messages ? [1] : []

        content {
          type = "CloudWatchLogProcessing"

          parameters {
            parameter_name  = "DataMessageExtraction"
            parameter_value = "true"
          }
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose[0].name
      log_stream_name = aws_cloudwatch_log_stream.firehose[0].name
    }
  }

  depends_on = [aws_iam_role_policy.firehose]

  tags = local.tags
}

# ------------------------------------------------------------------ CloudWatch Logs -> Firehose
data "aws_iam_policy_document" "logs_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
    }
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
    resources = ["arn:${local.partition}:firehose:${local.region}:${local.account_id}:deliverystream/${local.stream_name}"]
  }
}

resource "aws_iam_role" "logs" {
  count = local.n

  name                 = "${var.name_prefix}-logs-to-firehose"
  assume_role_policy   = data.aws_iam_policy_document.logs_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy" "logs" {
  count = local.n

  name   = "put-to-firehose"
  role   = aws_iam_role.logs[0].id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_cloudwatch_log_subscription_filter" "splunk" {
  for_each = var.enabled ? var.log_group_names : {}

  name            = "${var.name_prefix}-splunk"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.splunk[0].arn
  role_arn        = aws_iam_role.logs[0].arn

  depends_on = [aws_iam_role_policy.logs]
}

# ------------------------------------------------------------------ Delivery alarms
resource "aws_cloudwatch_metric_alarm" "delivery_success" {
  count = local.n

  alarm_name          = "${var.name_prefix}-splunk-delivery"
  alarm_description   = "Splunk rejects or cannot be reached - records go to s3://.../${var.failed_records_prefix}/ (check the Firehose error log)"
  namespace           = "AWS/Firehose"
  metric_name         = "DeliveryToSplunk.Success"
  dimensions          = { DeliveryStreamName = local.stream_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0.99
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "data_freshness" {
  count = local.n

  alarm_name          = "${var.name_prefix}-splunk-freshness"
  alarm_description   = "Oldest record not yet in Splunk > 15 minutes"
  namespace           = "AWS/Firehose"
  metric_name         = "DeliveryToSplunk.DataFreshness"
  dimensions          = { DeliveryStreamName = local.stream_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 900
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alert_topic_arn]
  ok_actions          = [var.alert_topic_arn]

  tags = local.tags
}

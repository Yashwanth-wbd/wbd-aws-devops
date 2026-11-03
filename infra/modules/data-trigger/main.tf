locals {
  name = "${var.name_prefix}-data-trigger"
  tags = merge(var.tags, { Component = "data-platform" })

  rules = {
    landing = jsonencode({
      source        = ["aws.s3"]
      "detail-type" = ["Object Created"]
      detail = {
        bucket = { name = [var.landing_bucket_name] }
        object = { key = [for bu in var.business_units : { prefix = "${bu}/" }] }
      }
    })
    ondemand = jsonencode({
      source        = [var.ondemand_source]
      "detail-type" = [var.ondemand_detail_type]
    })
  }
}

# ------------------------------------------------------------------ Dead-letter queue (failed deliveries and invocations)
resource "aws_sqs_queue" "dlq" {
  name                              = "${local.name}-dlq"
  message_retention_seconds         = 1209600
  kms_master_key_id                 = var.sqs_kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = local.tags
}

data "aws_iam_policy_document" "dlq" {
  statement {
    sid       = "EventBridgeDeadLetters"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for r in aws_cloudwatch_event_rule.this : r.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.dlq.json
}

# ------------------------------------------------------------------ Lambda
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.root}/.terraform/tmp/${local.name}.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name                 = "${local.name}-lambda"
  description          = "Data-trigger Lambda for ${var.name_prefix}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "lambda" {
  #checkov:skip=CKV_AWS_356:ENI management and X-Ray calls do not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:ENI management (Lambda in a VPC) does not support resource-level permissions.
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid = "VpcNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  # Only the Airflow User role of this environment: trigger DAG runs through the MWAA API.
  statement {
    sid       = "TriggerDagRun"
    actions   = ["airflow:InvokeRestApi"]
    resources = [var.airflow_role_arn]
  }

  statement {
    sid       = "DeadLetters"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  statement {
    sid       = "Keys"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.sqs_kms_key_arn, var.lambda_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "data-trigger"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer profiles from WBD; the zip is built from Git by Terraform.
  function_name    = local.name
  description      = "Starts one ${var.dag_id} run per landed file or on-demand request"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.lambda_kms_key_arn

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      MWAA_ENVIRONMENT = var.mwaa_environment_name
      DAG_ID           = var.dag_id
      APP_ENV          = var.environment
      ONDEMAND_SOURCE  = var.ondemand_source
      BUSINESS_UNITS   = jsonencode(var.business_units)
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  tags = local.tags

  depends_on = [aws_iam_role_policy.lambda]
}

# ------------------------------------------------------------------ EventBridge rules (default bus)
resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name          = "${local.name}-${each.key}"
  description   = each.key == "landing" ? "File landed in ${var.landing_bucket_name}" : "On-demand data refresh (${var.ondemand_source})"
  event_pattern = each.value

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.rules

  rule = aws_cloudwatch_event_rule.this[each.key].name
  arn  = aws_lambda_function.this.arn

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

resource "aws_lambda_permission" "events" {
  for_each = local.rules

  statement_id  = "AllowEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

# ------------------------------------------------------------------ Alarms
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.name}-errors"
  alarm_description   = "Data-trigger Lambda failed - a landed file or on-demand request may not have started a DAG run."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${local.name}-dlq-not-empty"
  alarm_description   = "Trigger events in ${aws_sqs_queue.dlq.name} - DAG runs were not started. Re-drive after fixing (runbook: data platform)."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

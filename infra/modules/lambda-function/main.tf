locals {
  full_name  = "${var.name_prefix}-${var.name}"
  tags       = merge(var.tags, { Component = var.component })
  source_dir = coalesce(var.source_dir, "${path.module}/seed")
}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = local.source_dir
  output_path = "${path.root}/.terraform/tmp/${local.full_name}.zip"
  excludes    = ["__pycache__", "tests"]
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.full_name}"
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

resource "aws_iam_role" "this" {
  name                 = "${local.full_name}-lambda"
  description          = "Lambda ${local.full_name}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "this" {
  #checkov:skip=CKV_AWS_356:ENI management and X-Ray calls do not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:ENI management (Lambda in a VPC) does not support resource-level permissions.
  source_policy_documents = [var.policy_json]

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
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

  statement {
    sid       = "EnvironmentKey"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = var.name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer profiles from WBD.
  #checkov:skip=CKV_AWS_116:Invoked synchronously (Step Functions / API Gateway); the caller retries and records failures.
  function_name    = local.full_name
  description      = var.description
  role             = aws_iam_role.this.arn
  runtime          = var.runtime
  handler          = var.handler
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = var.memory_size
  kms_key_arn      = var.kms_key_arn
  publish          = true

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = var.environment
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tags = merge(local.tags, { Name = local.full_name })

  # deploy.yml ships the app code after the first apply (pipeline_managed_code = true).
  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  depends_on = [aws_iam_role_policy.this]
}

# Callers invoke the alias; a deploy publishes a version and moves it, a rollback moves it back.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.full_name}-errors"
  alarm_description   = "${local.full_name} returned errors - check ${aws_cloudwatch_log_group.this.name}"
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

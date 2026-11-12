locals {
  function_name = "${var.name_prefix}-databricks-export"
  tags          = merge(var.tags, { Component = "data-platform" })
  key_arns      = distinct(concat(values(var.business_unit_keys), [var.default_key_arn]))
}

# ------------------------------------------------------------------ Code (DevOps-owned, in lambda/)
data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.root}/.terraform/tmp/${local.function_name}.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

# ------------------------------------------------------------------ Role
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
  name                 = "${local.function_name}-lambda"
  description          = "Databricks export Lambda of ${var.name_prefix} (Jobs API run-now / runs get, manifest)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "this" {
  #checkov:skip=CKV_AWS_356:ENI management and X-Ray do not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:ENI management (Lambda in a VPC) does not support resource-level permissions.
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
    sid       = "ServicePrincipalSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.service_principal_secret_arn]
  }

  statement {
    sid       = "JobIds"
    actions   = ["ssm:GetParameter"]
    resources = [var.job_ids_parameter_arn]
  }

  statement {
    sid       = "SecretAndEnvKey"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]
  }

  statement {
    sid       = "WriteManifest"
    actions   = ["s3:PutObject"]
    resources = ["${var.landing_bucket_arn}/${var.manifest_prefix}*/_manifest.json"]
  }

  statement {
    sid       = "ManifestKeys"
    actions   = ["kms:GenerateDataKey"]
    resources = local.key_arns
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "databricks-export"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

# ------------------------------------------------------------------ Function
resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer profiles from WBD; the zip is built from Git by Terraform.
  #checkov:skip=CKV_AWS_116:Invoked synchronously by Step Functions, which retries and catches failures; a DLQ would never receive anything.
  #checkov:skip=CKV_AWS_115:Concurrency is bounded by the state machines (one call per business unit and poll).
  function_name    = local.function_name
  description      = "Starts / polls the WBD Databricks export job of a business unit (Jobs API) for the model-refresh and model-monitor state machines"
  role             = aws_iam_role.this.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = var.timeout
  memory_size      = 256
  kms_key_arn      = var.secrets_kms_key_arn

  environment {
    variables = {
      DATABRICKS_HOST   = var.databricks_host
      SECRET_ID         = var.service_principal_secret_arn
      JOB_IDS_PARAMETER = var.job_ids_parameter_name
      BU_KEYS           = jsonencode(var.business_unit_keys)
      DEFAULT_KEY       = var.default_key_arn
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tags = merge(local.tags, { Name = local.function_name })

  depends_on = [aws_iam_role_policy.this]
}

# Retried errors (throttling) also count, so one datapoint is not paged: 2 of 3 periods.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "${local.function_name} failed in 2 of the last 3 periods of 5 minutes - Databricks auth, job id or workspace reachability (runbooks/databricks-export-failed.md)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.this.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

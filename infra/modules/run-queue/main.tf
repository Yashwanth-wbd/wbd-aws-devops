locals {
  queue_name      = "${var.name_prefix}-optimization-requests"
  dispatcher_name = "${var.name_prefix}-run-dispatcher"
  tags            = merge(var.tags, { Component = "optimization" })

  # A message must reach the DLQ only after it has had every chance: maxReceiveCount x visibility
  # is well above max_queue_wait_minutes, so waiting requests expire (metric) instead.
  visibility_timeout = var.dispatcher_timeout * 6
}

# ------------------------------------------------------------------ Queue + dead-letter queue
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.queue_name}-dlq"
  message_retention_seconds = 14 * 86400
  kms_master_key_id         = var.sqs_kms_key_arn

  tags = merge(local.tags, { Name = "${local.queue_name}-dlq" })
}

resource "aws_sqs_queue" "this" {
  name                       = local.queue_name
  visibility_timeout_seconds = local.visibility_timeout
  message_retention_seconds  = 4 * 86400
  receive_wait_time_seconds  = 20
  kms_master_key_id          = var.sqs_kms_key_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(local.tags, { Name = local.queue_name })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

data "aws_iam_policy_document" "tls_only" {
  for_each = { main = aws_sqs_queue.this.arn, dlq = aws_sqs_queue.dlq.arn }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [each.value]

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
}

resource "aws_sqs_queue_policy" "this" {
  for_each = { main = aws_sqs_queue.this.id, dlq = aws_sqs_queue.dlq.id }

  queue_url = each.value
  policy    = data.aws_iam_policy_document.tls_only[each.key].json
}

# ------------------------------------------------------------------ Dispatcher Lambda (DevOps-owned code in lambda/)
data "archive_file" "dispatcher" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.root}/.terraform/tmp/${local.dispatcher_name}.zip"
}

resource "aws_cloudwatch_log_group" "dispatcher" {
  name              = "/aws/lambda/${local.dispatcher_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dispatcher" {
  name                 = "${local.dispatcher_name}-lambda"
  description          = "Optimization run dispatcher of ${var.name_prefix}"
  assume_role_policy   = data.aws_iam_policy_document.lambda_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "dispatcher" {
  #checkov:skip=CKV_AWS_356:ENI management, X-Ray and PutMetricData do not support resource-level permissions (PutMetricData is limited by namespace).
  #checkov:skip=CKV_AWS_111:ENI management (Lambda in a VPC) does not support resource-level permissions.
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.dispatcher.arn}:*"]
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
    sid       = "ConsumeQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [aws_sqs_queue.this.arn]
  }

  statement {
    sid       = "Keys"
    actions   = ["kms:Decrypt"]
    resources = [var.sqs_kms_key_arn, var.env_kms_key_arn]
  }

  statement {
    sid       = "ReadRunLimit"
    actions   = ["ssm:GetParameter"]
    resources = [var.max_runs_parameter_arn]
  }

  statement {
    sid       = "CountRunning"
    actions   = ["states:ListExecutions"]
    resources = [var.state_machine_arn]
  }

  statement {
    sid       = "StartRun"
    actions   = ["states:StartExecution"]
    resources = [var.state_machine_arn]
  }

  statement {
    sid       = "QueueMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metric_namespace]
    }
  }
}

resource "aws_iam_role_policy" "dispatcher" {
  name   = "run-dispatcher"
  role   = aws_iam_role.dispatcher.id
  policy = data.aws_iam_policy_document.dispatcher.json
}

resource "aws_lambda_function" "dispatcher" {
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer profiles from WBD; the zip is built from Git by Terraform.
  #checkov:skip=CKV_AWS_116:SQS event source: failed messages stay on the queue and go to the queue's own DLQ.
  function_name    = local.dispatcher_name
  description      = "Starts queued optimization runs while fewer than max_concurrent_runs are running"
  role             = aws_iam_role.dispatcher.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.dispatcher.output_path
  source_code_hash = data.archive_file.dispatcher.output_base64sha256
  timeout          = var.dispatcher_timeout
  memory_size      = 256
  kms_key_arn      = var.env_kms_key_arn

  reserved_concurrent_executions = var.dispatcher_concurrency

  environment {
    variables = {
      STATE_MACHINE_ARN      = var.state_machine_arn
      MAX_RUNS_PARAMETER     = var.max_runs_parameter_name
      MAX_QUEUE_WAIT_SECONDS = tostring(var.max_queue_wait_minutes * 60)
      METRIC_NAMESPACE       = var.metric_namespace
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.dispatcher.name
  }

  tags = merge(local.tags, { Name = local.dispatcher_name })

  depends_on = [aws_iam_role_policy.dispatcher]
}

resource "aws_lambda_event_source_mapping" "dispatcher" {
  event_source_arn                   = aws_sqs_queue.this.arn
  function_name                      = aws_lambda_function.dispatcher.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = var.dispatcher_concurrency
  }
}

# ------------------------------------------------------------------ Alarms
locals {
  alarms = {
    oldest-request = {
      description = "A run request has waited more than ${var.oldest_message_alarm_minutes} minutes - all run slots busy or the dispatcher is failing (runbook optimization-run-failed)"
      namespace   = "AWS/SQS"
      metric      = "ApproximateAgeOfOldestMessage"
      dimensions  = { QueueName = aws_sqs_queue.this.name }
      statistic   = "Maximum"
      threshold   = var.oldest_message_alarm_minutes * 60
    }
    dlq-not-empty = {
      description = "Run requests in the DLQ - they failed ${var.max_receive_count} times (runbook optimization-run-failed: inspect, then redrive)"
      namespace   = "AWS/SQS"
      metric      = "ApproximateNumberOfMessagesVisible"
      dimensions  = { QueueName = aws_sqs_queue.dlq.name }
      statistic   = "Maximum"
      threshold   = 0
    }
    dispatcher-errors = {
      description = "${local.dispatcher_name} failed - check ${aws_cloudwatch_log_group.dispatcher.name}"
      namespace   = "AWS/Lambda"
      metric      = "Errors"
      dimensions  = { FunctionName = aws_lambda_function.dispatcher.function_name }
      statistic   = "Sum"
      threshold   = 0
    }
    dispatcher-throttles = {
      description = "${local.dispatcher_name} throttled - reserved concurrency and the event source maximum concurrency must match"
      namespace   = "AWS/Lambda"
      metric      = "Throttles"
      dimensions  = { FunctionName = aws_lambda_function.dispatcher.function_name }
      statistic   = "Sum"
      threshold   = 0
    }
    expired-requests = {
      description = "Run requests waited longer than ${var.max_queue_wait_minutes} minutes and were dropped - planners must resubmit; raise max_concurrent_runs (runbook scale-planning-season)"
      namespace   = var.metric_namespace
      metric      = "ExpiredRunRequests"
      dimensions  = { StateMachine = var.state_machine_name }
      statistic   = "Sum"
      threshold   = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name_prefix}-runs-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

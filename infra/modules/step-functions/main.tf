data "aws_caller_identity" "current" {}

locals {
  full_name = "${var.name_prefix}-${var.name}"
  tags      = merge(var.tags, { Component = var.component })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/states/${local.full_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${local.full_name}-sfn"
  description          = "Step Functions role of ${local.full_name}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

# Log delivery and X-Ray do not support resource-level permissions.
data "aws_iam_policy_document" "base" {
  #checkov:skip=CKV_AWS_111:CloudWatch Logs delivery APIs used by Step Functions do not support resource-level permissions.
  #checkov:skip=CKV_AWS_356:CloudWatch Logs delivery and X-Ray APIs do not support resource-level permissions.
  source_policy_documents = [var.role_policy_json]

  statement {
    sid = "LogDelivery"
    actions = [
      "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "state-machine"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.base.json
}

resource "aws_sfn_state_machine" "this" {
  name       = local.full_name
  role_arn   = aws_iam_role.this.arn
  type       = "STANDARD"
  definition = var.definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    include_execution_data = var.include_execution_data
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = merge(local.tags, { Name = local.full_name })

  depends_on = [aws_iam_role_policy.this]
}

# ------------------------------------------------------------------ Alarms
resource "aws_cloudwatch_metric_alarm" "failed" {
  alarm_name          = "${local.full_name}-failed"
  alarm_description   = "${local.full_name}: an execution failed, timed out or was aborted - see the execution history and ${aws_cloudwatch_log_group.this.name}"
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  metric_query {
    id          = "bad"
    expression  = "FILL(failed, 0) + FILL(timedout, 0) + FILL(aborted, 0)"
    label       = "Failed + timed out + aborted"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = { failed = "ExecutionsFailed", timedout = "ExecutionsTimedOut", aborted = "ExecutionsAborted" }

    content {
      id = metric_query.key

      metric {
        namespace   = "AWS/States"
        metric_name = metric_query.value
        dimensions  = { StateMachineArn = aws_sfn_state_machine.this.arn }
        stat        = "Sum"
        period      = 300
      }
    }
  }

  tags = local.tags
}

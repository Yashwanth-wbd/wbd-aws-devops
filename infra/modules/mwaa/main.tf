data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  name            = "${var.name_prefix}-airflow"
  environment_arn = "arn:${local.partition}:airflow:${local.region}:${local.account_id}:environment/${local.name}"
  log_group_arn   = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:airflow-${local.name}-*"
  secrets_arn     = "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${var.secrets_prefix}/*"

  bucket_objects = [for b in var.data_bucket_arns : "${b}/*"]

  # Airflow reads connections from Secrets Manager; [mmm] options become AIRFLOW__MMM__* for the DAGs.
  airflow_configuration_options = merge(
    {
      "secrets.backend"                  = "airflow.providers.amazon.aws.secrets.secrets_manager.SecretsManagerBackend"
      "secrets.backend_kwargs"           = jsonencode({ connections_prefix = "${var.secrets_prefix}/connections" })
      "core.load_examples"               = "False"
      "core.dags_are_paused_at_creation" = "False"
      "webserver.expose_config"          = "False"
    },
    { for k, v in var.dag_settings : "mmm.${k}" => v },
  )
}

# ------------------------------------------------------------------ Execution role
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["airflow.amazonaws.com", "airflow-env.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name                 = "${var.name_prefix}-mwaa-exec"
  description          = "MWAA execution role for ${local.name}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, { Component = "data-platform" })
}

data "aws_iam_policy_document" "execution" {
  #checkov:skip=CKV_AWS_356:cloudwatch:PutMetricData, logs:DescribeLogGroups and s3:GetAccountPublicAccessBlock do not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:cloudwatch:PutMetricData does not support resource-level permissions.
  statement {
    sid       = "PublishMetrics"
    actions   = ["airflow:PublishMetrics"]
    resources = [local.environment_arn]
  }

  statement {
    sid       = "DagsBucketRead"
    actions   = ["s3:GetObject*", "s3:GetBucket*", "s3:List*"]
    resources = [var.source_bucket_arn, "${var.source_bucket_arn}/*"]
  }

  statement {
    sid       = "AccountPublicAccessBlock"
    actions   = ["s3:GetAccountPublicAccessBlock"]
    resources = ["*"]
  }

  statement {
    sid = "AirflowLogs"
    actions = [
      "logs:CreateLogStream", "logs:CreateLogGroup", "logs:PutLogEvents", "logs:GetLogEvents",
      "logs:GetLogRecord", "logs:GetLogGroupFields", "logs:GetQueryResults",
    ]
    resources = [local.log_group_arn]
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "Metrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }

  # Celery queue that MWAA creates and owns (in an AWS service account).
  statement {
    sid = "CeleryQueue"
    actions = [
      "sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl", "sqs:ReceiveMessage", "sqs:SendMessage",
    ]
    resources = ["arn:${local.partition}:sqs:${local.region}:*:airflow-celery-*"]
  }

  statement {
    sid       = "EnvironmentKey"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey*", "kms:Encrypt"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["sqs.${local.region}.amazonaws.com", "s3.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "AirflowConnections"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [local.secrets_arn]
  }

  statement {
    sid       = "SecretsKey"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]
  }

  # DAG tasks: read landing, write run manifests and data-quality results.
  dynamic "statement" {
    for_each = length(var.data_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "DataBuckets"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      resources = concat(var.data_bucket_arns, local.bucket_objects)
    }
  }

  statement {
    sid       = "DataKeys"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = var.data_kms_key_arns
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "mwaa-execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ------------------------------------------------------------------ Environment (20-30 min to create)
resource "aws_mwaa_environment" "this" {
  name               = local.name
  airflow_version    = var.airflow_version
  environment_class  = var.environment_class
  min_workers        = var.min_workers
  max_workers        = var.max_workers
  schedulers         = var.schedulers
  execution_role_arn = aws_iam_role.execution.arn
  kms_key            = var.kms_key_arn

  source_bucket_arn = var.source_bucket_arn
  dag_s3_path       = "dags/"

  webserver_access_mode           = "PRIVATE_ONLY"
  weekly_maintenance_window_start = var.weekly_maintenance_window_start
  airflow_configuration_options   = local.airflow_configuration_options

  network_configuration {
    security_group_ids = [var.security_group_id]
    subnet_ids         = slice(var.subnet_ids, 0, 2)
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = var.log_level
    }
    scheduler_logs {
      enabled   = true
      log_level = var.log_level
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = var.log_level
    }
    worker_logs {
      enabled   = true
      log_level = var.log_level
    }
  }

  tags = merge(var.tags, { Component = "data-platform" })

  # data.yml uploads requirements.txt and sets its path and version (Terraform would undo that).
  lifecycle {
    ignore_changes = [
      requirements_s3_path, requirements_s3_object_version,
      plugins_s3_path, plugins_s3_object_version,
      startup_script_s3_path, startup_script_s3_object_version,
    ]
  }

  depends_on = [aws_iam_role_policy.execution]
}

# ------------------------------------------------------------------ Alarm: scheduler stopped
resource "aws_cloudwatch_metric_alarm" "scheduler_heartbeat" {
  alarm_name          = "${local.name}-scheduler-heartbeat"
  alarm_description   = "MWAA scheduler sent no heartbeat for 15 minutes - no DAG runs start. See runbook: data platform."
  namespace           = "AmazonMWAA"
  metric_name         = "SchedulerHeartbeat"
  dimensions          = { Function = "Scheduler", Environment = local.name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = merge(var.tags, { Component = "data-platform" })

  depends_on = [aws_mwaa_environment.this]
}

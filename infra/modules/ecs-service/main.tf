data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  full_name = "${var.name_prefix}-${var.service_name}"
  log_group = "/ecs/${var.name_prefix}/${var.service_name}"

  tags = merge(var.tags, { Component = "ecs", Service = local.full_name })

  otel_volume = "opentelemetry-auto-instrumentation-python"

  otel_env = var.enable_application_signals ? {
    OTEL_RESOURCE_ATTRIBUTES                       = "service.name=${local.full_name},deployment.environment=${var.name_prefix}"
    OTEL_AWS_APPLICATION_SIGNALS_ENABLED           = "true"
    OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT = "http://localhost:4316/v1/metrics"
    OTEL_EXPORTER_OTLP_PROTOCOL                    = "http/protobuf"
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT             = "http://localhost:4316/v1/traces"
    OTEL_TRACES_SAMPLER                            = "xray"
    OTEL_TRACES_SAMPLER_ARG                        = "endpoint=http://localhost:2000"
    OTEL_METRICS_EXPORTER                          = "none"
    OTEL_LOGS_EXPORTER                             = "none"
    OTEL_PYTHON_DISTRO                             = "aws_distro"
    OTEL_PYTHON_CONFIGURATOR                       = "aws_configurator"
    PYTHONPATH                                     = "/otel-auto-instrumentation-python/opentelemetry/instrumentation/auto_instrumentation:/otel-auto-instrumentation-python"
  } : {}

  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = local.log_group
      awslogs-region        = local.region
      awslogs-stream-prefix = var.service_name
    }
  }

  # Unset optional fields (null) are dropped so ECS uses the image defaults.
  app_container = { for k, v in local.app_container_all : k => v if v != null }

  app_container_all = {
    name                   = "app"
    image                  = var.image
    essential              = true
    command                = var.command
    entryPoint             = var.entry_point
    user                   = var.user
    privileged             = false
    readonlyRootFilesystem = true
    linuxParameters        = { initProcessEnabled = true }
    environment            = [for k, v in merge(var.environment, local.otel_env) : { name = k, value = v }]
    secrets                = [for k, v in var.secrets : { name = k, valueFrom = v }]
    portMappings           = var.container_port == null ? [] : [{ name = "http", containerPort = var.container_port, protocol = "tcp", appProtocol = "http" }]
    mountPoints = [
      for m in [
        { sourceVolume = "tmp", containerPath = "/tmp", readOnly = false, on = true },
        { sourceVolume = local.otel_volume, containerPath = "/otel-auto-instrumentation-python", readOnly = false, on = var.enable_application_signals },
      ] : { sourceVolume = m.sourceVolume, containerPath = m.containerPath, readOnly = m.readOnly } if m.on
    ]
    dependsOn        = var.enable_application_signals ? [{ containerName = "otel-init", condition = "SUCCESS" }] : null
    logConfiguration = local.log_config
  }

  sidecars = slice([
    {
      name                   = "otel-init"
      image                  = var.adot_python_image
      essential              = false
      user                   = var.user
      privileged             = false
      readonlyRootFilesystem = true
      command                = ["cp", "-a", "/autoinstrumentation/.", "/otel-auto-instrumentation-python"]
      mountPoints            = [{ sourceVolume = local.otel_volume, containerPath = "/otel-auto-instrumentation-python", readOnly = false }]
      logConfiguration       = local.log_config
    },
    {
      name                   = "cloudwatch-agent"
      image                  = var.cloudwatch_agent_image
      essential              = false
      privileged             = false
      readonlyRootFilesystem = false
      environment = [{
        name  = "CW_CONFIG_CONTENT"
        value = jsonencode({ traces = { traces_collected = { application_signals = {} } }, logs = { metrics_collected = { application_signals = {} } } })
      }]
      logConfiguration = local.log_config
    },
  ], 0, var.enable_application_signals ? 2 : 0)
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

# ------------------------------------------------------------------ Task role (the app's own identity)
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "task" {
  name                 = "${var.name_prefix}-task-${var.task_role_suffix}"
  description          = "Task role of ${local.full_name}"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy" "app" {
  name   = "app"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_json
}

data "aws_iam_policy_document" "exec_command" {
  count = var.enable_execute_command ? 1 : 0

  statement {
    sid       = "EcsExecChannels"
    actions   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    resources = ["*"]
  }

  statement {
    sid       = "EcsExecAuditLog"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${var.exec_audit_log_group_arn}:*"]
  }

  statement {
    sid       = "EcsExecDescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "EcsExecSessionKey"
    actions   = ["kms:Decrypt"]
    resources = [var.exec_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "exec_command" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.exec_command[0].json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count = var.enable_application_signals ? 1 : 0

  role       = aws_iam_role.task.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ------------------------------------------------------------------ Seed task definition
resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  volume {
    name = "tmp"
  }

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_gib == null ? [] : [var.ephemeral_storage_gib]

    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  dynamic "volume" {
    for_each = var.enable_application_signals ? [1] : []

    content {
      name = local.otel_volume
    }
  }

  container_definitions = jsonencode(concat([local.app_container], local.sidecars))

  tags = local.tags

  lifecycle {
    precondition {
      condition     = !var.enable_execute_command || (var.exec_audit_log_group_arn != null && var.exec_kms_key_arn != null)
      error_message = "exec_audit_log_group_arn and exec_kms_key_arn are required when enable_execute_command = true."
    }
  }
}

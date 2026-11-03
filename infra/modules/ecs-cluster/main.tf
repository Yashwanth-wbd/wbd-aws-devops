data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  region       = data.aws_region.current.name
  cluster_name = "${var.name_prefix}-ecs"

  tags = merge(var.tags, { Component = "ecs" })
}

# ------------------------------------------------------------------ Cluster
# Who ran which command in ECS Exec (break-glass shell) is kept here.
resource "aws_cloudwatch_log_group" "exec" {
  name              = "/ecs/${var.name_prefix}/exec-audit"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enhanced"
  }

  configuration {
    execute_command_configuration {
      kms_key_id = var.logs_kms_key_arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
        cloud_watch_encryption_enabled = true
      }
    }
  }

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.this.arn
  }

  tags = merge(local.tags, { Name = local.cluster_name })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = 1
  }
}

# Service Connect: services call each other by name (e.g. http://genai-gateway:8080 in Release 2).
resource "aws_service_discovery_http_namespace" "this" {
  name        = "${var.name_prefix}.internal"
  description = "Service Connect namespace for ${local.cluster_name}"

  tags = local.tags
}

# ------------------------------------------------------------------ Task execution role (shared)
# Used by the ECS agent before the app starts: pull the image, create log streams, inject secrets.
data "aws_iam_policy_document" "exec_assume" {
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
  }
}

resource "aws_iam_role" "exec" {
  name                 = "${var.name_prefix}-ecs-task-exec"
  description          = "ECS task execution role for ${local.cluster_name}"
  assume_role_policy   = data.aws_iam_policy_document.exec_assume.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "exec" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = ["arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/mmm/*"]
  }

  statement {
    sid       = "EcrDecrypt"
    actions   = ["kms:Decrypt"]
    resources = [var.ecr_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ecr.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "WriteServiceLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.name_prefix}/*:*"]
  }

  statement {
    sid       = "InjectListedSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }

  statement {
    sid       = "InjectParameters"
    actions   = ["ssm:GetParameters"]
    resources = [var.parameter_path_arn]
  }

  statement {
    sid       = "DecryptSecrets"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com", "ssm.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "exec" {
  name   = "task-execution"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.exec.json
}

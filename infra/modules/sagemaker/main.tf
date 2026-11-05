data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  role_name  = "${var.name_prefix}-sagemaker-${var.name}"
  tags       = merge(var.tags, { Component = "sagemaker" })

  read_objects  = [for b in var.read_bucket_arns : "${b}/*"]
  write_objects = [for b in var.write_bucket_arns : "${b}/*"]
}

# ------------------------------------------------------------------ Job execution role
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "SageMaker ${var.name} jobs of ${var.name_prefix} (VPC only)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "this" {
  #checkov:skip=CKV_AWS_111:EC2 network-interface management for VPC jobs does not support resource-level permissions.
  #checkov:skip=CKV_AWS_356:EC2 Describe*, ecr:GetAuthorizationToken and cloudwatch:PutMetricData do not support resource-level permissions.
  #checkov:skip=CKV_AWS_109:SageMaker VPC jobs need ec2:CreateNetworkInterfacePermission, which has no resource-level scope.
  statement {
    sid = "VpcNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:CreateNetworkInterfacePermission", "ec2:DeleteNetworkInterface",
      "ec2:DeleteNetworkInterfacePermission", "ec2:DescribeNetworkInterfaces", "ec2:DescribeVpcs",
      "ec2:DescribeDhcpOptions", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = var.ecr_repository_arns
  }

  statement {
    sid       = "JobLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/sagemaker/*"]
  }

  statement {
    sid       = "JobMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "cloudwatch:namespace"
      values   = ["/aws/sagemaker/*", "MMM*"]
    }
  }

  statement {
    sid       = "ReadInputs"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = concat(var.read_bucket_arns, local.read_objects)
  }

  dynamic "statement" {
    for_each = length(var.write_bucket_arns) > 0 ? [1] : []
    content {
      sid       = "WriteOutputs"
      actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:AbortMultipartUpload", "s3:GetBucketLocation"]
      resources = concat(var.write_bucket_arns, local.write_objects)
    }
  }

  statement {
    sid       = "DataKeys"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = concat(var.data_kms_key_arns, [var.volume_kms_key_arn])
  }

  # SageMaker encrypts the job's ML storage volume through a grant on the volume key.
  statement {
    sid       = "VolumeKeyGrant"
    actions   = ["kms:CreateGrant"]
    resources = [var.volume_kms_key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "sagemaker-${var.name}"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

# ------------------------------------------------------------------ Model Registry (training side only)
resource "aws_sagemaker_model_package_group" "this" {
  for_each = toset(var.model_package_groups)

  model_package_group_name        = "${var.name_prefix}-${each.key}"
  model_package_group_description = "MMM model versions for business unit ${each.key}; Approved = used by optimization"

  tags = merge(local.tags, { BusinessUnit = each.key })
}

# Approval changes (model-governance.yml) and new candidates are announced on the alert topic.
resource "aws_cloudwatch_event_rule" "model_package" {
  count = length(var.model_package_groups) > 0 ? 1 : 0

  name        = "${var.name_prefix}-model-package-state"
  description = "Model package created, approved or rejected in ${var.name_prefix} model groups"
  event_pattern = jsonencode({
    source        = ["aws.sagemaker"]
    "detail-type" = ["SageMaker Model Package State Change"]
    detail        = { ModelPackageGroupName = [for g in aws_sagemaker_model_package_group.this : g.model_package_group_name] }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "model_package" {
  count = length(var.model_package_groups) > 0 ? 1 : 0

  rule      = aws_cloudwatch_event_rule.model_package[0].name
  target_id = "sns"
  arn       = var.notification_topic_arn

  input_transformer {
    input_paths = {
      group   = "$.detail.ModelPackageGroupName"
      version = "$.detail.ModelPackageVersion"
      status  = "$.detail.ModelApprovalStatus"
    }
    input_template = "\"Model <group> version <version>: <status>. Approve or reject with model-governance.yml.\""
  }
}

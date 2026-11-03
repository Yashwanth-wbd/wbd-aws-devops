data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  tags       = merge(var.tags, { Component = "monitoring" })
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  alarm_arns = "arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"
  rule_arns  = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/*"
}

# Own key: CloudWatch and EventBridge must be named in the key policy to publish to an encrypted topic.
data "aws_iam_policy_document" "alerts_key" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_111:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_356:Key policy; "*" means this key only and IAM policies then decide who can use it.
  statement {
    sid       = "EnableIAMPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AlarmAndEventPublishers"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description             = "${var.name_prefix} alert topic encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.alerts_key.json

  tags = merge(local.tags, { Name = "${var.name_prefix}-alerts" })
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = "${var.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn

  tags = merge(local.tags, { Name = "${var.name_prefix}-alerts" })
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "AccountOwnerManages"
    actions   = ["sns:Publish", "sns:Subscribe", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:ListSubscriptionsByTopic"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.alarm_arns]
    }
  }

  statement {
    sid       = "EventBridgeRulesPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.rule_arns]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

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

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

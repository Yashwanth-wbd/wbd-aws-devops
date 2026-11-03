# CLOUDFRONT-scope resources must be created in us-east-1.
data "aws_caller_identity" "current" {
  provider = aws.us_east_1
}

data "aws_partition" "current" {
  provider = aws.us_east_1
}

locals {
  managed_rule_groups = {
    ip-reputation = { priority = 10, name = "AWSManagedRulesAmazonIpReputationList" }
    common        = { priority = 20, name = "AWSManagedRulesCommonRuleSet" }
    known-bad     = { priority = 30, name = "AWSManagedRulesKnownBadInputsRuleSet" }
    sqli          = { priority = 40, name = "AWSManagedRulesSQLiRuleSet" }
  }
  waf_log_group_name = "aws-waf-logs-${var.name_prefix}"
  create_waf_log_key = var.create_waf_log_kms_key
}

resource "aws_wafv2_web_acl" "this" {
  #checkov:skip=CKV_AWS_192:AWSManagedRulesKnownBadInputsRuleSet (Log4j) is included through the dynamic block below.
  provider = aws.us_east_1

  name        = "${var.name_prefix}-cdn"
  description = "MMM front door: AWS managed rules and per-IP rate limit"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups

    content {
      name     = rule.key
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value.name

          dynamic "rule_action_override" {
            for_each = rule.key == "common" ? var.waf_count_only_rules : []

            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 50

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cdn"
    sampled_requests_enabled   = true
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-cdn" })
}

# ------------------------------------------------------------------ WAF logs (Step 9 forwards them to Splunk)
data "aws_iam_policy_document" "waf_log_key" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_111:Key policy; "*" means this key only and IAM policies then decide who can use it.
  #checkov:skip=CKV_AWS_356:Key policy; "*" means this key only and IAM policies then decide who can use it.
  count    = local.create_waf_log_key ? 1 : 0
  provider = aws.us_east_1

  statement {
    sid       = "EnableIAMPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchLogsUsEast1"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "waf_logs" {
  count    = local.create_waf_log_key ? 1 : 0
  provider = aws.us_east_1

  description             = "${var.name_prefix} WAF log encryption (us-east-1)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.waf_log_key[0].json

  tags = merge(local.tags, { Name = "${var.name_prefix}-waf-logs" })
}

resource "aws_kms_alias" "waf_logs" {
  count    = local.create_waf_log_key ? 1 : 0
  provider = aws.us_east_1

  name          = "alias/${var.name_prefix}-waf-logs"
  target_key_id = aws_kms_key.waf_logs[0].key_id
}

resource "aws_cloudwatch_log_group" "waf" {
  provider = aws.us_east_1

  name              = local.waf_log_group_name
  retention_in_days = var.waf_log_retention_days
  kms_key_id        = local.create_waf_log_key ? aws_kms_key.waf_logs[0].arn : var.waf_log_kms_key_arn

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.create_waf_log_key || var.waf_log_kms_key_arn != null
      error_message = "Set waf_log_kms_key_arn when create_waf_log_kms_key = false."
    }
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  provider = aws.us_east_1

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # Okta tokens and session cookies never reach the logs.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

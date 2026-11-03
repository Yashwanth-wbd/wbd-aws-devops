data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  policy_name = "${var.name_prefix}-permission-boundary"
  policy_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${local.policy_name}"

  # Global services are called through us-east-1 (or have no region), so the region lock skips them.
  global_actions = [
    "iam:*", "sts:*", "organizations:*", "account:*", "support:*", "health:*",
    "budgets:*", "ce:*", "cur:*", "pricing:*", "cloudfront:*", "route53:*",
    "route53domains:*", "waf:*", "shield:*", "globalaccelerator:*", "trustedadvisor:*",
    "sso:*", "identitystore:*", "s3:GetBucketLocation", "s3:ListAllMyBuckets",
  ]
}

data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_107:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_108:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_109:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_110:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_111:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_356:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_1:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_49:Permission boundary; it caps permissions and grants nothing on its own.

  # A boundary only limits; the role's own policies still have to grant each action.
  statement {
    sid       = "AllowWithinBoundary"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIamUsersAndKeys"
    effect = "Deny"
    actions = [
      "iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy", "iam:PutUserPolicy", "iam:AddUserToGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyChangingThisBoundary"
    effect    = "Deny"
    actions   = ["iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]
    resources = [local.policy_arn]
  }

  statement {
    sid       = "DenyRemovingBoundaryFromRoles"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyRolesWithoutThisBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.policy_arn]
    }
  }

  statement {
    sid    = "DenyDisablingSecurityServices"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
      "guardduty:DeleteDetector", "guardduty:UpdateDetector", "guardduty:DisassociateFromMasterAccount",
      "guardduty:DisassociateFromAdministratorAccount", "guardduty:DeleteMembers", "guardduty:StopMonitoringMembers",
      "securityhub:DisableSecurityHub", "securityhub:DisassociateFromMasterAccount",
      "securityhub:DisassociateFromAdministratorAccount", "securityhub:BatchDisableStandards",
      "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:DeleteDeliveryChannel",
      "access-analyzer:DeleteAnalyzer", "inspector2:Disable", "macie2:DisableMacie",
    ]
    resources = ["*"]
  }

  statement {
    sid         = "DenyUnapprovedRegions"
    effect      = "Deny"
    not_actions = local.global_actions
    resources   = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }
}

resource "aws_iam_policy" "boundary" {
  #checkov:skip=CKV_AWS_62:Permission boundary; "*" is the ceiling, the deny statements are the controls.
  #checkov:skip=CKV_AWS_63:Permission boundary; "*" is the ceiling, the deny statements are the controls.
  #checkov:skip=CKV_AWS_286:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_287:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_288:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_289:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_290:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV_AWS_355:Permission boundary; it caps permissions and grants nothing on its own.
  #checkov:skip=CKV2_AWS_40:Permission boundary; it caps permissions and grants nothing on its own.
  name        = local.policy_name
  description = "Permission boundary for every IAM role created by Terraform in ${var.name_prefix}."
  policy      = data.aws_iam_policy_document.boundary.json

  tags = merge(var.tags, { Component = "iam" })
}

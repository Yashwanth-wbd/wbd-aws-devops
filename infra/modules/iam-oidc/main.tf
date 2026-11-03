data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  repo       = "repo:${var.github_org}/${var.github_repo}"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  cluster_arn    = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:cluster/${var.name_prefix}-ecs"
  ecr_repo_arns  = "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${var.ecr_repository_prefix}/*"
  state_bucket   = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  secrets_prefix = "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:mmm/${var.env_short}/*"

  env_subject = "${local.repo}:environment:${var.environment}"

  subjects = {
    plan = concat(
      [local.env_subject],
      var.plan_allow_pull_requests ? ["${local.repo}:pull_request"] : [],
      var.plan_allow_main_branch ? ["${local.repo}:ref:refs/heads/main"] : [],
    )
    apply    = [local.env_subject]
    deploy   = [local.env_subject]
    ecr_push = concat([local.env_subject], var.ecr_push_allow_main_branch ? ["${local.repo}:ref:refs/heads/main"] : [])
    ecr_read = [for e in var.ecr_read_trusted_environments : "${local.repo}:environment:${e}"]
  }

  roles = {
    plan     = { name = "${var.name_prefix}-gha-plan", create = true }
    apply    = { name = "${var.name_prefix}-gha-apply", create = true }
    deploy   = { name = "${var.name_prefix}-gha-deploy", create = true }
    ecr_push = { name = "${var.name_prefix}-gha-ecr-push", create = true }
    ecr_read = { name = "${var.name_prefix}-gha-ecr-read", create = length(var.ecr_read_trusted_environments) > 0 }
  }
  created_roles = { for k, r in local.roles : k => r if r.create }
}

# ------------------------------------------------------------------ OIDC provider (one per account)
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub's certificate itself; the API still requires a value.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = merge(var.tags, { Component = "iam" })
}

# ------------------------------------------------------------------ Trust policies
data "aws_iam_policy_document" "trust" {
  for_each = local.created_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subjects[each.key]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.created_roles

  name                 = each.value.name
  description          = "GitHub Actions ${each.key} role for ${var.name_prefix}"
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = var.max_session_duration

  tags = merge(var.tags, { Component = "cicd" })
}

# ------------------------------------------------------------------ gha-plan: read-only + state + secret refresh
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.this["plan"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "StateLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket}/*.tflock"]
  }

  statement {
    sid       = "StateKms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.state_kms_key_arn]
  }

  # terraform plan refreshes generated secret versions, which needs read access to their values.
  statement {
    sid       = "RefreshProjectSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.secrets_prefix]
  }

  statement {
    sid       = "DecryptProjectSecrets"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.this["plan"].id
  policy = data.aws_iam_policy_document.plan.json
}

# ------------------------------------------------------------------ gha-apply: Terraform, capped by the boundary
resource "aws_iam_role_policy_attachment" "apply_admin" {
  #checkov:skip=CKV_AWS_274:Terraform apply role; capped by the permission boundary and only assumable from the approved GitHub Environment.
  role       = aws_iam_role.this["apply"].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

# ------------------------------------------------------------------ gha-deploy: ECS deploy + frontend only
data "aws_iam_policy_document" "deploy" {
  #checkov:skip=CKV_AWS_356:RegisterTaskDefinition and the Describe/List calls do not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:RegisterTaskDefinition does not support resource-level permissions.
  statement {
    sid       = "TaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions"]
    resources = ["*"]
  }

  statement {
    sid       = "UpdateServices"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.name_prefix}-ecs/${var.name_prefix}-*"]
  }

  statement {
    sid       = "RunMigrationTask"
    actions   = ["ecs:RunTask"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${var.name_prefix}-migrate:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [local.cluster_arn]
    }
  }

  statement {
    sid       = "WatchTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${var.name_prefix}-ecs/*"]
  }

  statement {
    sid     = "TagOnCreate"
    actions = ["ecs:TagResource"]
    resources = [
      "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${var.name_prefix}-*:*",
      "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${var.name_prefix}-ecs/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition", "RunTask"]
    }
  }

  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.name_prefix}-task-*",
      "arn:${local.partition}:iam::${local.account_id}:role/${var.name_prefix}-ecs-task-exec",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "ReadMigrationLogs"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.name_prefix}/*"]
  }

  statement {
    sid     = "PreMigrationSnapshot"
    actions = ["rds:CreateDBSnapshot", "rds:AddTagsToResource"]
    resources = [
      "arn:${local.partition}:rds:${local.region}:${local.account_id}:db:${var.name_prefix}-pg",
      "arn:${local.partition}:rds:${local.region}:${local.account_id}:snapshot:${var.name_prefix}-*",
    ]
  }

  statement {
    sid       = "DescribeDatabase"
    actions   = ["rds:DescribeDBSnapshots", "rds:DescribeDBInstances"]
    resources = ["*"]
  }

  statement {
    sid       = "CheckImageExists"
    actions   = ["ecr:DescribeImages"]
    resources = [local.ecr_repo_arns]
  }

  statement {
    sid     = "FrontendUpload"
    actions = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [
      "arn:${local.partition}:s3:::wbd-mmm-${var.env_short}-frontend-*",
      "arn:${local.partition}:s3:::wbd-mmm-${var.env_short}-frontend-*/*",
    ]
  }

  statement {
    sid       = "FrontendKms"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.s3_kms_key_arn]
  }

  statement {
    sid       = "FrontendCloudFront"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:GetDistribution"]
    resources = ["arn:${local.partition}:cloudfront::${local.account_id}:distribution/*"]
  }

  # The frontend release switch: key current_release in the edge key value store.
  statement {
    sid       = "FrontendReleasePointer"
    actions   = ["cloudfront-keyvaluestore:DescribeKeyValueStore", "cloudfront-keyvaluestore:GetKey", "cloudfront-keyvaluestore:PutKey"]
    resources = ["arn:${local.partition}:cloudfront::${local.account_id}:key-value-store/*"]
  }

  # Public Okta settings written into the frontend's config.json.
  statement {
    sid       = "FrontendConfig"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/mmm/${var.env_short}/okta/*"]
  }

  # data.yml (Step 13): DAGs + requirements.txt to the MWAA bucket, quality suites, MWAA update.
  dynamic "statement" {
    for_each = var.enable_data_deploy ? [1] : []
    content {
      sid     = "DataUpload"
      actions = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      resources = [
        "arn:${local.partition}:s3:::wbd-mmm-${var.env_short}-mwaa-*",
        "arn:${local.partition}:s3:::wbd-mmm-${var.env_short}-mwaa-*/*",
        "arn:${local.partition}:s3:::wbd-mmm-${var.env_short}-data-quality-*",
        "arn:${local.partition}:s3:::wbd-mmm-${var.env_short}-data-quality-*/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = var.enable_data_deploy ? [1] : []
    content {
      sid       = "MwaaRequirements"
      actions   = ["airflow:GetEnvironment", "airflow:UpdateEnvironment"]
      resources = ["arn:${local.partition}:airflow:${local.region}:${local.account_id}:environment/${var.name_prefix}-airflow"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_data_deploy ? [1] : []
    content {
      sid       = "MwaaPassExecutionRole"
      actions   = ["iam:PassRole"]
      resources = ["arn:${local.partition}:iam::${local.account_id}:role/${var.name_prefix}-mwaa-exec"]

      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["airflow.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "ecs-deploy"
  role   = aws_iam_role.this["deploy"].id
  policy = data.aws_iam_policy_document.deploy.json
}

# ------------------------------------------------------------------ gha-ecr-push / gha-ecr-read
data "aws_iam_policy_document" "ecr_push" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "Login"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushAndPull"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages", "ecr:DescribeRepositories",
    ]
    resources = [local.ecr_repo_arns]
  }

  statement {
    sid       = "EcrKms"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.ecr_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.this["ecr_push"].id
  policy = data.aws_iam_policy_document.ecr_push.json
}

data "aws_iam_policy_document" "ecr_read" {
  #checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken does not support resource-level permissions.
  statement {
    sid       = "Login"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "Pull"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages", "ecr:DescribeRepositories",
    ]
    resources = [local.ecr_repo_arns]
  }

  statement {
    sid       = "EcrKms"
    actions   = ["kms:Decrypt"]
    resources = [var.ecr_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ecr_read" {
  count = local.roles.ecr_read.create ? 1 : 0

  name   = "ecr-read"
  role   = aws_iam_role.this["ecr_read"].id
  policy = data.aws_iam_policy_document.ecr_read.json
}

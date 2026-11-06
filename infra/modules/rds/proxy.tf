locals {
  # Admin first, then the app/migration users. The proxy reads each secret to log in to the DB.
  proxy_secret_arns = concat([aws_db_instance.this.master_user_secret[0].secret_arn], var.proxy_user_secret_arns)
}

data "aws_iam_policy_document" "proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name                 = "${local.identifier}-proxy"
  assume_role_policy   = data.aws_iam_policy_document.proxy_assume.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "proxy" {
  statement {
    sid       = "ReadProxySecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.proxy_secret_arns
  }

  statement {
    sid       = "DecryptProxySecrets"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "proxy" {
  name   = "read-proxy-secrets"
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy.json
}

# One pooled entry point for ECS tasks and the results-publisher Lambda (many short connections).
resource "aws_db_proxy" "this" {
  name                   = "${local.identifier}-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [var.proxy_security_group_id]
  require_tls            = true
  idle_client_timeout    = 1800
  debug_logging          = false

  # Clients log in with an IAM auth token (rds-db:connect on their own DB user), never a password.
  dynamic "auth" {
    for_each = local.proxy_secret_arns

    content {
      auth_scheme               = "SECRETS"
      iam_auth                  = "REQUIRED"
      client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
      secret_arn                = auth.value
    }
  }

  tags = merge(local.tags, { Name = "${local.identifier}-proxy" })

  depends_on = [aws_iam_role_policy.proxy]
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
    connection_borrow_timeout    = 120
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = aws_db_instance.this.identifier
}

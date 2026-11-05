data "aws_region" "current" {}

locals {
  tags        = merge(var.tags, { Component = "auth" })
  pool_name   = "${var.name_prefix}-users"
  app_url     = "https://${var.app_domain_name}"
  domain_host = "${var.domain_prefix}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

# Users only come from the WBD IdP (Okta, MFA enforced there); nobody signs up or gets a local password.
resource "aws_cognito_user_pool" "this" {
  name                = local.pool_name
  deletion_protection = var.deletion_protection ? "ACTIVE" : "INACTIVE"
  mfa_configuration   = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "admin_only"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  # IdP group membership, copied on every sign-in; the API maps it to MMM roles (docs/06).
  schema {
    name                     = "groups"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false
    required                 = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  tags = merge(local.tags, { Name = local.pool_name })

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "aws_cognito_identity_provider" "wbd" {
  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = var.idp_name
  provider_type = "SAML"

  provider_details = {
    MetadataURL = var.saml_metadata_url
    IDPSignout  = "false"
  }

  attribute_mapping = {
    email           = var.saml_attribute_email
    name            = var.saml_attribute_name
    "custom:groups" = var.saml_attribute_groups
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

# Confidential client used by the ALB authenticate-cognito action (authorization code flow).
resource "aws_cognito_user_pool_client" "alb" {
  name         = "${var.name_prefix}-alb"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = [aws_cognito_identity_provider.wbd.provider_name]
  callback_urls                        = ["${local.app_url}/oauth2/idpresponse"]
  logout_urls                          = ["${local.app_url}/"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = var.session_hours

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "hours"
  }

  read_attributes = ["email", "name", "custom:groups"]
}

# ================================================================== Step 8 - Private entry and sign-in
# Internal application, no public entry:
# WBD user (WBD network / VPN) -> WBD DNS (app name -> internal ALB) -> Transit Gateway
# -> internal ALB in the private-app subnets (TLS 1.2+, only alb_ingress_cidrs = WBD ranges)
# -> sign-in with WBD Okta first (OIDC authenticate action, MFA in Okta)
# -> UI tasks (/*) and API tasks (/api/*). Unauthenticated /api/* calls get 401; only
# /api/health is open (health checks, smoke test).
# Until okta_sign_in_enabled = true (client secret stored in mmm/<env>/okta/alb-client) the ALB
# answers 503 on everything except /api/health - the app is never reachable without sign-in.
locals {
  app_url = "https://${var.app_domain_name}"

  # Org authorization server (https://<org>.okta.com) or custom one (https://<org>.okta.com/oauth2/<id>)
  okta_issuer   = trimsuffix(var.okta_issuer, "/")
  okta_base     = strcontains(local.okta_issuer, "/oauth2/") ? local.okta_issuer : "${local.okta_issuer}/oauth2"
  okta_endpoint = { for e in ["authorize", "token", "userinfo", "logout"] : e => "${local.okta_base}/v1/${e}" }

  okta_logout_url = "${local.okta_endpoint.logout}?client_id=${var.okta_client_id}&post_logout_redirect_uri=${urlencode("${local.app_url}/")}"
}

data "aws_secretsmanager_secret_version" "okta" {
  count = var.okta_sign_in_enabled ? 1 : 0

  secret_id = module.secrets.secret_arns["okta/alb-client"]
}

# ------------------------------------------------------------------ Internal ALB
module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  internal          = true
  subnet_ids        = module.network.private_app_subnet_ids
  security_group_id = module.network.security_group_ids["alb"]
  certificate_arn   = var.alb_certificate_arn
  app_port          = local.app_port
  ui_port           = local.ui_port

  oidc = var.okta_sign_in_enabled ? {
    issuer                 = local.okta_issuer
    authorization_endpoint = local.okta_endpoint.authorize
    token_endpoint         = local.okta_endpoint.token
    user_info_endpoint     = local.okta_endpoint.userinfo
    client_id              = var.okta_client_id
    session_seconds        = var.session_hours * 3600
  } : null
  oidc_client_secret = var.okta_sign_in_enabled ? jsondecode(data.aws_secretsmanager_secret_version.okta[0].secret_string)["client_secret"] : null

  access_log_bucket   = module.log_bucket.bucket_name
  access_log_prefix   = module.log_bucket.prefixes.alb
  deletion_protection = local.is_prod
}

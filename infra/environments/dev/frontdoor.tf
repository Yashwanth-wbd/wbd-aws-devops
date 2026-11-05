# ================================================================== Step 8 - Front door and sign-in
# Browser -> public ALB (regional WAF, TLS 1.2+) -> Cognito sign-in federated to WBD Okta (SAML)
# -> UI tasks (/*) and API tasks (/api/*). Unauthenticated /api/* calls get 401; only
# /api/health is open (health checks, smoke test).
locals {
  app_url = "https://${var.app_domain_name}"
}

# ------------------------------------------------------------------ Cognito (WBD Okta federation)
module "cognito" {
  source = "../../modules/cognito"

  name_prefix         = local.name_prefix
  app_domain_name     = var.app_domain_name
  domain_prefix       = coalesce(var.cognito_domain_prefix, "wbd-mmm-${local.env_short}")
  saml_metadata_url   = var.okta_saml_metadata_url
  session_hours       = var.session_hours
  deletion_protection = local.is_prod
}

# ------------------------------------------------------------------ ALB
module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  security_group_id = module.network.security_group_ids["alb"]
  certificate_arn   = var.alb_certificate_arn
  app_port          = local.app_port
  ui_port           = local.ui_port

  cognito = {
    user_pool_arn   = module.cognito.user_pool_arn
    client_id       = module.cognito.client_id
    domain_prefix   = module.cognito.domain_prefix
    session_seconds = var.session_hours * 3600
  }

  access_log_bucket   = module.log_bucket.bucket_name
  access_log_prefix   = module.log_bucket.prefixes.alb
  deletion_protection = local.is_prod
}

# ------------------------------------------------------------------ Regional WAF on the ALB
module "waf" {
  source = "../../modules/waf-regional"

  name_prefix         = local.name_prefix
  alb_arn             = module.alb.alb_arn
  rate_limit          = var.waf_rate_limit
  geo_allow_countries = var.geo_allow_countries
  count_only_rules    = var.waf_count_only
  logs_kms_key_arn    = module.kms.key_arns["logs"]
  log_retention_days  = var.log_retention_days
}

# ------------------------------------------------------------------ DNS (optional)
# With a Route 53 zone in this account the record is created here; otherwise WBD DNS adds the
# CNAME from the output dns_records_for_wbd.
resource "aws_route53_record" "app" {
  count = var.route53_zone_id == null ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.app_domain_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

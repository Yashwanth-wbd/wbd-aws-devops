locals {
  security_groups = merge(
    {
      endpoints    = "Interface VPC endpoints - HTTPS from inside the VPC"
      alb          = "Public ALB - HTTPS (and HTTP for the redirect) from the allowed ranges; WAF in front"
      api          = "API tasks - app port from the ALB only"
      ui           = "UI tasks - web port from the ALB only"
      tasks        = "One-off ECS tasks (platform check, DB bootstrap) - no inbound, HTTPS out"
      data_clients = "Attach to anything that uses the database - PostgreSQL to RDS Proxy"
      rds_proxy    = "RDS Proxy - PostgreSQL from data clients only"
      rds          = "RDS PostgreSQL - from RDS Proxy only"
      sagemaker    = "SageMaker jobs - traffic between job instances, HTTPS to VPC endpoints and S3 only"
      lambda       = "VPC Lambda functions (results publisher, run dispatcher) - no inbound, HTTPS to VPC endpoints and S3"
    },
    var.enable_resolver_forwarding ? { resolver = "Route 53 Resolver outbound endpoint - DNS to WBD servers" } : {},
    var.create_genai_security_group ? { genai = "LLM gateway proxy Lambda - no inbound, HTTPS out to the approved LLM providers and VPC endpoints" } : {},
  )

  # One rule per allowed CIDR and port; 80 only redirects to 443 at the ALB.
  alb_ingress_rules = {
    for p in setproduct(var.alb_ingress_cidrs, [443, 80]) :
    "alb_${p[1]}_from_${replace(replace(p[0], ".", "_"), "/", "_")}" => {
      sg = "alb", description = "${p[1] == 443 ? "HTTPS" : "HTTP (redirect)"} from ${p[0]}", protocol = "tcp", port = p[1],
    cidr = p[0], prefix_list = null, source_sg = null, enabled = true }
  }

  # Every rule has all fields so the map has one object type; unused fields are null.
  static_ingress_rules = {
    endpoints_https_from_vpc = { sg = "endpoints", description = "HTTPS from the VPC", protocol = "tcp", port = 443, cidr = var.vpc_cidr, prefix_list = null, source_sg = null, enabled = true }
    api_from_alb             = { sg = "api", description = "App port from the ALB", protocol = "tcp", port = var.app_port, cidr = null, prefix_list = null, source_sg = "alb", enabled = true }
    ui_from_alb              = { sg = "ui", description = "Web port from the ALB", protocol = "tcp", port = var.ui_port, cidr = null, prefix_list = null, source_sg = "alb", enabled = true }
    rds_proxy_from_clients   = { sg = "rds_proxy", description = "PostgreSQL from data clients", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "data_clients", enabled = true }
    rds_from_proxy           = { sg = "rds", description = "PostgreSQL from RDS Proxy", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "rds_proxy", enabled = true }
    sagemaker_from_self      = { sg = "sagemaker", description = "Between instances of one job (distributed training)", protocol = "-1", port = null, cidr = null, prefix_list = null, source_sg = "sagemaker", enabled = true }
  }

  ingress_rules = merge(local.static_ingress_rules, local.alb_ingress_rules)

  s3_prefix_list = aws_vpc_endpoint.gateway["s3"].prefix_list_id

  static_egress_rules = {
    alb_to_api                = { sg = "alb", description = "App port to API tasks", protocol = "tcp", port = var.app_port, cidr = null, prefix_list = null, source_sg = "api", enabled = true }
    alb_to_ui                 = { sg = "alb", description = "Web port to UI tasks", protocol = "tcp", port = var.ui_port, cidr = null, prefix_list = null, source_sg = "ui", enabled = true }
    alb_https_out             = { sg = "alb", description = "HTTPS to Okta (authenticate-oidc token and user info calls)", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = true }
    api_https_out             = { sg = "api", description = "HTTPS to AWS endpoints, S3 and the ALB token-signing keys", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = true }
    ui_to_endpoints           = { sg = "ui", description = "HTTPS to interface endpoints (ECR, logs)", protocol = "tcp", port = 443, cidr = null, prefix_list = null, source_sg = "endpoints", enabled = true }
    ui_to_s3                  = { sg = "ui", description = "HTTPS to S3 gateway endpoint (ECR layers)", protocol = "tcp", port = 443, cidr = null, prefix_list = local.s3_prefix_list, source_sg = null, enabled = true }
    tasks_https_out           = { sg = "tasks", description = "HTTPS to AWS endpoints, S3 and package indexes (bootstrap)", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = true }
    data_clients_to_proxy     = { sg = "data_clients", description = "PostgreSQL to RDS Proxy", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "rds_proxy", enabled = true }
    data_clients_to_endpoints = { sg = "data_clients", description = "HTTPS to interface endpoints (ECR, logs, secrets)", protocol = "tcp", port = 443, cidr = null, prefix_list = null, source_sg = "endpoints", enabled = true }
    data_clients_to_s3        = { sg = "data_clients", description = "HTTPS to S3 gateway endpoint (ECR layers)", protocol = "tcp", port = 443, cidr = null, prefix_list = local.s3_prefix_list, source_sg = null, enabled = true }
    rds_proxy_to_rds          = { sg = "rds_proxy", description = "PostgreSQL to the RDS instance", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "rds", enabled = true }
    sagemaker_to_self         = { sg = "sagemaker", description = "Between instances of one job (distributed training)", protocol = "-1", port = null, cidr = null, prefix_list = null, source_sg = "sagemaker", enabled = true }
    sagemaker_to_endpoints    = { sg = "sagemaker", description = "HTTPS to interface endpoints (ECR, logs, STS, KMS, SageMaker API)", protocol = "tcp", port = 443, cidr = null, prefix_list = null, source_sg = "endpoints", enabled = true }
    sagemaker_to_s3           = { sg = "sagemaker", description = "HTTPS to S3 gateway endpoint (data, models, outputs)", protocol = "tcp", port = 443, cidr = null, prefix_list = local.s3_prefix_list, source_sg = null, enabled = true }
    lambda_to_endpoints       = { sg = "lambda", description = "HTTPS to interface endpoints (logs, STS, KMS)", protocol = "tcp", port = 443, cidr = null, prefix_list = null, source_sg = "endpoints", enabled = true }
    lambda_to_s3              = { sg = "lambda", description = "HTTPS to S3 gateway endpoint (run evidence)", protocol = "tcp", port = 443, cidr = null, prefix_list = local.s3_prefix_list, source_sg = null, enabled = true }
    genai_https_out           = { sg = "genai", description = "HTTPS to the approved LLM providers and VPC endpoints", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = var.create_genai_security_group }
  }

  resolver_egress_rules = {
    for p in setproduct(var.resolver_target_ips, ["tcp", "udp"]) :
    "resolver_dns_${p[1]}_${replace(p[0], ".", "_")}" => {
      sg = "resolver", description = "DNS (${p[1]}) to WBD server ${p[0]}", protocol = p[1], port = 53,
    cidr = "${p[0]}/32", prefix_list = null, source_sg = null, enabled = var.enable_resolver_forwarding }
  }

  enabled_ingress_rules = { for k, r in local.ingress_rules : k => r if r.enabled }
  enabled_egress_rules  = { for k, r in merge(local.static_egress_rules, local.resolver_egress_rules) : k => r if r.enabled }
}

resource "aws_security_group" "this" {
  #checkov:skip=CKV2_AWS_5:Attached by the ALB, ECS, RDS, SageMaker and Lambda resources of the environment stack.
  for_each = local.security_groups

  name        = "${var.name_prefix}-${replace(each.key, "_", "-")}-sg"
  description = each.value
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-${replace(each.key, "_", "-")}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  #checkov:skip=CKV_AWS_260:Port 80 on the public ALB only answers with a redirect to HTTPS; the WAF filters both.
  for_each = local.enabled_ingress_rules

  security_group_id            = aws_security_group.this[each.value.sg].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr
  prefix_list_id               = each.value.prefix_list
  referenced_security_group_id = each.value.source_sg == null ? null : aws_security_group.this[each.value.source_sg].id

  tags = merge(local.tags, { Name = "${var.name_prefix}-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.enabled_egress_rules

  security_group_id            = aws_security_group.this[each.value.sg].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  cidr_ipv4                    = each.value.cidr
  prefix_list_id               = each.value.prefix_list
  referenced_security_group_id = each.value.source_sg == null ? null : aws_security_group.this[each.value.source_sg].id

  tags = merge(local.tags, { Name = "${var.name_prefix}-${each.key}" })
}

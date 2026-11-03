data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  security_groups = merge(
    {
      endpoints    = "Interface VPC endpoints - HTTPS from inside the VPC"
      alb          = "ALB - HTTPS from CloudFront origin-facing IPs only"
      api          = "API tasks - app port from the ALB only"
      workers      = "What-if and optimizer worker tasks - no inbound"
      data_clients = "Attach to any task that uses the database - PostgreSQL to RDS Proxy"
      rds_proxy    = "RDS Proxy - PostgreSQL from data clients only"
      rds          = "RDS PostgreSQL - from RDS Proxy only"
      redis        = "ElastiCache - from API and worker tasks only"
    },
    var.create_mwaa_security_group ? {
      mwaa         = "MWAA environment - self-referencing as required by MWAA"
      data_trigger = "Data-trigger Lambda - no inbound, HTTPS out (MWAA API)"
    } : {},
    var.enable_resolver_forwarding ? { resolver = "Route 53 Resolver outbound endpoint - DNS to WBD servers" } : {},
  )

  # Every rule has all fields so the map has one object type; unused fields are null.
  ingress_rules = {
    endpoints_https_from_vpc  = { sg = "endpoints", description = "HTTPS from the VPC", protocol = "tcp", port = 443, cidr = var.vpc_cidr, prefix_list = null, source_sg = null, enabled = true }
    alb_https_from_cloudfront = { sg = "alb", description = "HTTPS from CloudFront origin-facing prefix list", protocol = "tcp", port = 443, cidr = null, prefix_list = data.aws_ec2_managed_prefix_list.cloudfront.id, source_sg = null, enabled = true }
    api_from_alb              = { sg = "api", description = "App port from the ALB", protocol = "tcp", port = var.app_port, cidr = null, prefix_list = null, source_sg = "alb", enabled = true }
    rds_proxy_from_clients    = { sg = "rds_proxy", description = "PostgreSQL from data clients", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "data_clients", enabled = true }
    rds_from_proxy            = { sg = "rds", description = "PostgreSQL from RDS Proxy", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "rds_proxy", enabled = true }
    redis_from_api            = { sg = "redis", description = "Redis TLS from API tasks", protocol = "tcp", port = 6379, cidr = null, prefix_list = null, source_sg = "api", enabled = true }
    redis_from_workers        = { sg = "redis", description = "Redis TLS from worker tasks", protocol = "tcp", port = 6379, cidr = null, prefix_list = null, source_sg = "workers", enabled = true }
    mwaa_from_self            = { sg = "mwaa", description = "All traffic between MWAA components", protocol = "-1", port = null, cidr = null, prefix_list = null, source_sg = "mwaa", enabled = var.create_mwaa_security_group }
  }

  static_egress_rules = {
    alb_to_api                = { sg = "alb", description = "App port to API tasks", protocol = "tcp", port = var.app_port, cidr = null, prefix_list = null, source_sg = "api", enabled = true }
    api_https_out             = { sg = "api", description = "HTTPS to AWS endpoints, S3 and Okta", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = true }
    api_to_redis              = { sg = "api", description = "Redis TLS", protocol = "tcp", port = 6379, cidr = null, prefix_list = null, source_sg = "redis", enabled = true }
    workers_https_out         = { sg = "workers", description = "HTTPS to AWS endpoints, S3 and Databricks", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = true }
    workers_to_redis          = { sg = "workers", description = "Redis TLS", protocol = "tcp", port = 6379, cidr = null, prefix_list = null, source_sg = "redis", enabled = true }
    data_clients_to_proxy     = { sg = "data_clients", description = "PostgreSQL to RDS Proxy", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "rds_proxy", enabled = true }
    data_clients_to_endpoints = { sg = "data_clients", description = "HTTPS to interface endpoints (ECR, logs, secrets)", protocol = "tcp", port = 443, cidr = null, prefix_list = null, source_sg = "endpoints", enabled = true }
    data_clients_to_s3        = { sg = "data_clients", description = "HTTPS to S3 gateway endpoint (ECR layers)", protocol = "tcp", port = 443, cidr = null, prefix_list = aws_vpc_endpoint.gateway["s3"].prefix_list_id, source_sg = null, enabled = true }
    rds_proxy_to_rds          = { sg = "rds_proxy", description = "PostgreSQL to RDS", protocol = "tcp", port = 5432, cidr = null, prefix_list = null, source_sg = "rds", enabled = true }
    mwaa_to_self              = { sg = "mwaa", description = "All traffic between MWAA components", protocol = "-1", port = null, cidr = null, prefix_list = null, source_sg = "mwaa", enabled = var.create_mwaa_security_group }
    mwaa_https_out            = { sg = "mwaa", description = "HTTPS to AWS endpoints, S3, PyPI and Databricks", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = var.create_mwaa_security_group }
    data_trigger_https_out    = { sg = "data_trigger", description = "HTTPS to the MWAA API and AWS endpoints", protocol = "tcp", port = 443, cidr = "0.0.0.0/0", prefix_list = null, source_sg = null, enabled = var.create_mwaa_security_group }
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
  #checkov:skip=CKV2_AWS_5:Attached by the ALB, ECS, RDS, ElastiCache and MWAA modules in later steps.
  for_each = local.security_groups

  name        = "${var.name_prefix}-${replace(each.key, "_", "-")}-sg"
  description = each.value
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-${replace(each.key, "_", "-")}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
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

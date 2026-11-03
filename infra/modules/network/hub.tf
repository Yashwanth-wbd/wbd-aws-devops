# Optional WBD hub connectivity. Everything here is off until WBD Network shares the details.

# ------------------------------------------------------------------ Transit Gateway
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.enable_transit_gateway ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for s in aws_subnet.endpoint : s.id]
  dns_support        = "enable"

  tags = merge(local.tags, { Name = "${var.name_prefix}-tgw-attachment" })

  lifecycle {
    precondition {
      condition     = var.transit_gateway_id != null && startswith(coalesce(var.transit_gateway_id, "none"), "tgw-")
      error_message = "transit_gateway_id must be set (tgw-...) when enable_transit_gateway = true."
    }
  }
}

resource "aws_route" "app_tgw" {
  for_each = var.enable_transit_gateway ? {
    for p in setproduct(local.azs, var.transit_gateway_routes) : "${p[0]}|${p[1]}" => { az = p[0], cidr = p[1] }
  } : {}

  route_table_id         = aws_route_table.app[each.value.az].id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]

  lifecycle {
    precondition {
      condition     = !(var.enable_nat_gateway && each.value.cidr == "0.0.0.0/0")
      error_message = "0.0.0.0/0 can go to the Transit Gateway only when enable_nat_gateway = false."
    }
  }
}

# ------------------------------------------------------------------ Route 53 Resolver forwarding
resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.enable_resolver_forwarding ? 1 : 0

  name               = "${var.name_prefix}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.this["resolver"].id]

  dynamic "ip_address" {
    for_each = aws_subnet.endpoint

    content {
      subnet_id = ip_address.value.id
    }
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-resolver-outbound" })

  lifecycle {
    precondition {
      condition     = length(var.resolver_forward_domains) > 0 && length(var.resolver_target_ips) > 0
      error_message = "resolver_forward_domains and resolver_target_ips are required when enable_resolver_forwarding = true."
    }
  }
}

resource "aws_route53_resolver_rule" "forward" {
  for_each = var.enable_resolver_forwarding ? toset(var.resolver_forward_domains) : toset([])

  name                 = "${var.name_prefix}-fwd-${replace(each.key, ".", "-")}"
  domain_name          = each.key
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = var.resolver_target_ips

    content {
      ip   = target_ip.value
      port = 53
    }
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-fwd-${replace(each.key, ".", "-")}" })
}

resource "aws_route53_resolver_rule_association" "forward" {
  for_each = aws_route53_resolver_rule.forward

  resolver_rule_id = each.value.id
  vpc_id           = aws_vpc.this.id
}

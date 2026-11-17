# WBD hub connectivity. The ALB is internal, so the Transit Gateway is how WBD users reach the app:
# WBD network -> Transit Gateway -> private-app subnets (internal ALB). Return traffic to the WBD
# ranges uses the app route tables (aws_route.app_tgw). WBD DNS (outside AWS) resolves the app name.

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

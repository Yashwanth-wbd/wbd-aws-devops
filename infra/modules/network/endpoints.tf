# Gateway endpoints are free; S3 also carries ECR image layers, so image pulls never use NAT.
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(["s3", "dynamodb"])

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for rt in aws_route_table.app : rt.id], [aws_route_table.data.id])

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-${each.key}" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.endpoint : s.id]
  security_group_ids  = [aws_security_group.this["endpoints"].id]

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-${replace(each.key, ".", "-")}" })
}

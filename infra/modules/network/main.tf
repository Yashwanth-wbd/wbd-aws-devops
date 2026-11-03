data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "selected" {
  filter {
    name   = "zone-id"
    values = var.availability_zone_ids
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  tags = merge(var.tags, { Component = "network" })

  # AZ names in the order of var.availability_zone_ids
  az_name_by_id = zipmap(data.aws_availability_zones.selected.zone_ids, data.aws_availability_zones.selected.names)
  azs           = [for id in var.availability_zone_ids : local.az_name_by_id[id]]
  az_index      = { for i, az in local.azs : az => i }
  az_count      = length(local.azs)

  # The VPC is cut into eight equal blocks (/22 each for a /19):
  #   0-2 private-app, one block per AZ (ECS awsvpc tasks need many IPs)
  #   3   spare (4th AZ or growth)
  #   4   public, 5 private-data, 6 private-endpoint - each split into four /24s, one per AZ
  #   7   spare
  subnet_cidrs = {
    app      = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 3, i)]
    public   = [for i in range(local.az_count) : cidrsubnet(cidrsubnet(var.vpc_cidr, 3, 4), 2, i)]
    data     = [for i in range(local.az_count) : cidrsubnet(cidrsubnet(var.vpc_cidr, 3, 5), 2, i)]
    endpoint = [for i in range(local.az_count) : cidrsubnet(cidrsubnet(var.vpc_cidr, 3, 6), 2, i)]
  }

  nat_azs = var.enable_nat_gateway ? (var.single_nat_gateway ? [local.azs[0]] : local.azs) : []
}

# ------------------------------------------------------------------ VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpc" })
}

# Removes all rules from the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-default-sg-unused" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-igw" })
}

# ------------------------------------------------------------------ Subnets
resource "aws_subnet" "public" {
  for_each = local.az_index

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = local.subnet_cidrs.public[each.value]
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${var.name_prefix}-public-${each.key}", Tier = "public" })
}

resource "aws_subnet" "app" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.app[each.value]

  tags = merge(local.tags, { Name = "${var.name_prefix}-private-app-${each.key}", Tier = "private-app" })
}

resource "aws_subnet" "data" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.data[each.value]

  tags = merge(local.tags, { Name = "${var.name_prefix}-private-data-${each.key}", Tier = "private-data" })
}

resource "aws_subnet" "endpoint" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.endpoint[each.value]

  tags = merge(local.tags, { Name = "${var.name_prefix}-private-endpoint-${each.key}", Tier = "private-endpoint" })
}

# ------------------------------------------------------------------ NAT
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name_prefix}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.tags, { Name = "${var.name_prefix}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# ------------------------------------------------------------------ Route tables
# public: internet through the IGW (ALB and NAT only)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-public-rt", Tier = "public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# private-app: one table per AZ so each AZ can use its own NAT gateway
resource "aws_route_table" "app" {
  for_each = local.az_index

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-private-app-rt-${each.key}", Tier = "private-app" })
}

resource "aws_route" "app_nat" {
  for_each = var.enable_nat_gateway ? local.az_index : {}

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? local.azs[0] : each.key].id
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# private-data: VPC-local only - no internet route, no Transit Gateway route
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-private-data-rt", Tier = "private-data" })
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}

# private-endpoint: VPC-local only (interface endpoints, resolver, TGW attachment ENIs)
resource "aws_route_table" "endpoint" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-private-endpoint-rt", Tier = "private-endpoint" })
}

resource "aws_route_table_association" "endpoint" {
  for_each = aws_subnet.endpoint

  subnet_id      = each.value.id
  route_table_id = aws_route_table.endpoint.id
}

locals {
  id       = "${var.name_prefix}-redis"
  failover = var.num_cache_clusters > 1
  family   = var.engine == "valkey" ? "valkey${split(".", var.engine_version)[0]}" : "redis${split(".", var.engine_version)[0]}"

  tags = merge(var.tags, { Component = "elasticache" })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.id}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.id}-subnets" })
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(["slow-log", "engine-log"])

  name              = "/aws/elasticache/${local.id}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = local.id
  description          = "${var.name_prefix} what-if cache and job status"
  engine               = var.engine
  engine_version       = var.engine_version
  parameter_group_name = "default.${local.family}"
  node_type            = var.node_type
  port                 = 6379

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.failover
  multi_az_enabled           = local.failover

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]

  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = var.auth_token
  auth_token_update_strategy = "ROTATE"
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn

  snapshot_retention_limit   = var.snapshot_retention_days
  snapshot_window            = "03:00-04:00"
  maintenance_window         = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  dynamic "log_delivery_configuration" {
    for_each = aws_cloudwatch_log_group.this

    content {
      destination      = log_delivery_configuration.value.name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = log_delivery_configuration.key
    }
  }

  tags = merge(local.tags, { Name = local.id })
}

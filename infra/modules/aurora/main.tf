data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  identifier = "${var.name_prefix}-aurora"
  family     = "aurora-postgresql${split(".", var.engine_version)[0]}"

  # Writer first; readers are failover targets in another AZ (staging/prod).
  instances = { for i in range(var.instance_count) : format("%02d", i + 1) => i }

  tags = merge(var.tags, { Component = "aurora" })
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.identifier}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.identifier}-subnets" })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${local.identifier}-cluster-params"
  family = local.family

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pgaudit.log"
    value = var.pgaudit_log
  }

  parameter {
    name  = "pgaudit.role"
    value = "rds_pgaudit"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = merge(local.tags, { Name = "${local.identifier}-cluster-params" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "this" {
  name   = "${local.identifier}-instance-params"
  family = local.family

  tags = merge(local.tags, { Name = "${local.identifier}-instance-params" })

  lifecycle {
    create_before_destroy = true
  }
}

# Aurora writes exported logs here; creating the group first sets KMS and retention.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/rds/cluster/${local.identifier}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

# ------------------------------------------------------------------ Enhanced Monitoring role
data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name                 = "${local.identifier}-monitoring"
  assume_role_policy   = data.aws_iam_policy_document.monitoring_assume.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ------------------------------------------------------------------ Cluster (Serverless v2)
resource "aws_rds_cluster" "this" {
  #checkov:skip=CKV_AWS_139:Deletion protection is set per environment (on in prod).
  #checkov:skip=CKV_AWS_162:IAM authentication is enforced at RDS Proxy (iam_auth = REQUIRED); clients never connect to the cluster directly.
  #checkov:skip=CKV2_AWS_8:AWS Backup selects the cluster by tag (backup = true) in the environment backup plan.
  cluster_identifier = local.identifier
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version

  database_name                 = var.db_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.secrets_kms_key_arn

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.db_security_group_id]
  port                            = 5432
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  backup_retention_period             = var.backup_retention_days
  preferred_backup_window             = "02:00-03:00"
  preferred_maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.identifier}-final"
  allow_major_version_upgrade         = false
  apply_immediately                   = var.apply_immediately

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }

  tags = merge(local.tags, var.cluster_tags, { Name = local.identifier })

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_rds_cluster_instance" "this" {
  for_each = local.instances

  identifier         = "${local.identifier}-${each.key}"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = "db.serverless"

  db_subnet_group_name    = aws_db_subnet_group.this.name
  db_parameter_group_name = aws_db_parameter_group.this.name
  publicly_accessible     = false
  ca_cert_identifier      = "rds-ca-rsa2048-g1"
  promotion_tier          = each.value

  auto_minor_version_upgrade            = true
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7
  apply_immediately                     = var.apply_immediately

  tags = merge(local.tags, { Name = "${local.identifier}-${each.key}" })

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

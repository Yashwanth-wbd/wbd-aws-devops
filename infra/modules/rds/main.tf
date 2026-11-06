data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  identifier = "${var.name_prefix}-postgres"
  family     = "postgres${split(".", var.engine_version)[0]}"

  tags = merge(var.tags, { Component = "rds" })
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.identifier}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.identifier}-subnets" })
}

resource "aws_db_parameter_group" "this" {
  name   = "${local.identifier}-params"
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

  tags = merge(local.tags, { Name = "${local.identifier}-params" })

  lifecycle {
    create_before_destroy = true
  }
}

# RDS writes exported logs here; creating the groups first sets KMS and retention.
resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(["postgresql", "upgrade"])

  name              = "/aws/rds/instance/${local.identifier}/${each.key}"
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

# ------------------------------------------------------------------ DB instance
resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_293:Deletion protection is set per environment (on in prod).
  #checkov:skip=CKV_AWS_157:Multi-AZ is set per environment (staging and prod); dev runs single-AZ to save cost.
  #checkov:skip=CKV2_AWS_60:copy_tags_to_snapshot is set; the check also asks for it on read replicas, which are not built.
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name                       = var.db_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.secrets_kms_key_arn

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false
  port                   = 5432
  parameter_group_name   = aws_db_parameter_group.this.name
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  backup_retention_period             = var.backup_retention_days
  backup_window                       = "02:00-03:00"
  maintenance_window                  = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot               = true
  delete_automated_backups            = false
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.identifier}-final"
  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = false
  apply_immediately                   = var.apply_immediately

  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7

  tags = merge(local.tags, var.instance_tags, { Name = local.identifier })

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy_attachment.monitoring]
}

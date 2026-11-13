data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  tags       = merge(var.tags, { Component = "data-platform" })

  db_prefix  = replace(var.name_prefix, "-", "_")
  layers     = ["bronze", "silver", "gold"]
  databases  = { for l in local.layers : l => "${local.db_prefix}_${l}" }
  log_group  = "/aws-glue/jobs/${var.name_prefix}"
  s3_arn     = "arn:${local.partition}:s3:::"
  glue_arn   = "arn:${local.partition}:glue:${local.region}:${local.account_id}"
  role_name  = "${var.name_prefix}-glue"
  ruleset    = "${var.name_prefix}-silver"
  connection = "${var.name_prefix}-glue-vpc"

  # Medallion jobs, run per business unit by the model-refresh / model-monitor state machines
  # (glue:startJobRun.sync). Runtime arguments (--business_unit, --run_id, --raw_uri,
  # --snapshot_uri, --output_uri, --monitor_uri) come from the state machine; data/README.md has the
  # contract, including the lineage table properties every job writes to the Data Catalog.
  # Glue has no database access: export-rds only writes Parquet, the results/data publisher loads RDS.
  jobs = {
    bronze          = { description = "Raw Databricks export (Parquet in landing raw/databricks/<bu>/) -> Bronze Delta tables (ingested raw)", bookmarks = true }
    silver          = { description = "Bronze -> Silver Delta tables (cleansed, validated with Glue Data Quality ruleset ${local.ruleset})", bookmarks = false }
    gold            = { description = "Silver -> Gold per-BU modeling tables (adstock and saturation features)", bookmarks = false }
    export-training = { description = "Gold -> immutable Parquet training snapshot + metadata in the training-data bucket", bookmarks = false }
    export-rds      = { description = "Gold reference tables -> Parquet + _manifest.json in lakehouse ${var.rds_export_prefix}<bu>/<refresh_id>/ (loaded into RDS by the results/data publisher)", bookmarks = false }
    export-monitor  = { description = "Gold latest features -> lakehouse monitoring/<bu>/<date>/ for the drift check", bookmarks = false }
  }

  common_arguments = {
    "--job-language"                     = "python"
    "--datalake-formats"                 = "delta"
    "--conf"                             = "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension --conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog"
    "--enable-glue-datacatalog"          = "true"
    "--enable-metrics"                   = "true"
    "--enable-observability-metrics"     = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"          = local.log_group
    "--ENV"                              = var.environment
    "--LANDING_BUCKET"                   = var.landing_bucket_name
    "--LAKEHOUSE_BUCKET"                 = var.lakehouse_bucket_name
    "--TRAINING_DATA_BUCKET"             = var.training_data_bucket_name
    "--BRONZE_DATABASE"                  = local.databases["bronze"]
    "--SILVER_DATABASE"                  = local.databases["silver"]
    "--GOLD_DATABASE"                    = local.databases["gold"]
  }

  job_arguments = {
    silver     = { "--DQ_RULESET" = local.ruleset }
    export-rds = { "--RDS_EXPORT_PREFIX" = var.rds_export_prefix }
  }

  seed_script = <<-EOT
    # Seed placeholder created by Terraform. glue.yml replaces it with data/glue/jobs/<job>.py.
    raise SystemExit("seed Glue script - release data/glue/jobs with the glue workflow first")
  EOT
}

# ------------------------------------------------------------------ Data Catalog
resource "aws_glue_catalog_database" "this" {
  for_each = local.databases

  name         = each.value
  description  = "MMM ${each.key} layer (${var.name_prefix}) - Delta tables in s3://${var.lakehouse_bucket_name}/${each.key}/"
  location_uri = "s3://${var.lakehouse_bucket_name}/${each.key}/"

  tags = local.tags
}

# Account-wide: one setting per account and region.
resource "aws_glue_data_catalog_encryption_settings" "this" {
  count = var.manage_catalog_encryption ? 1 : 0

  data_catalog_encryption_settings {
    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id      = var.s3_kms_key_arn
    }

    connection_password_encryption {
      return_connection_password_encrypted = true
      aws_kms_key_id                       = var.s3_kms_key_arn
    }
  }
}

# ------------------------------------------------------------------ Encryption of what Glue writes itself
resource "aws_glue_security_configuration" "this" {
  name = "${var.name_prefix}-glue"

  encryption_configuration {
    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.s3_kms_key_arn
    }

    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = var.logs_kms_key_arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = var.s3_kms_key_arn
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

# ------------------------------------------------------------------ VPC placement (no internet: S3 gateway + interface endpoints)
resource "aws_glue_connection" "vpc" {
  name            = local.connection
  description     = "Places the ${var.name_prefix} Glue jobs in the private-app subnet (S3 gateway and VPC endpoints only, no database path)"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = var.availability_zone
    subnet_id              = var.subnet_id
    security_group_id_list = var.security_group_ids
  }

  tags = local.tags
}

# ------------------------------------------------------------------ Silver data quality
resource "aws_glue_data_quality_ruleset" "silver" {
  name        = local.ruleset
  description = "Rules the Silver layer must pass (data engineers, data/glue/dq/silver.dqdl); a failure stops the model refresh"
  ruleset     = var.silver_ruleset

  tags = local.tags
}

# ------------------------------------------------------------------ Job role
data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  description          = "Glue jobs of ${var.name_prefix} (Bronze / Silver / Gold and exports)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "this" {
  #checkov:skip=CKV_AWS_356:EC2 Describe calls and ENI creation for the Glue connection and PutMetricData (limited by namespace) have no resource-level permissions.
  #checkov:skip=CKV_AWS_111:ec2:CreateNetworkInterface for the Glue connection does not support resource-level permissions.
  statement {
    sid       = "Scripts"
    actions   = ["s3:GetObject"]
    resources = ["${local.s3_arn}${var.assets_bucket_name}/scripts/*"]
  }

  statement {
    sid       = "TempDir"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.s3_arn}${var.assets_bucket_name}/temp/*"]
  }

  statement {
    sid       = "ReadRawExport"
    actions   = ["s3:GetObject"]
    resources = ["${local.s3_arn}${var.landing_bucket_name}/raw/*"]
  }

  statement {
    sid       = "Lakehouse"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.s3_arn}${var.lakehouse_bucket_name}/*"]
  }

  # Object Lock bucket: snapshots are written once, never deleted.
  statement {
    sid       = "TrainingSnapshots"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${local.s3_arn}${var.training_data_bucket_name}/*"]
  }

  statement {
    sid     = "ListBuckets"
    actions = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [for b in [var.assets_bucket_name, var.landing_bucket_name, var.lakehouse_bucket_name, var.training_data_bucket_name] :
    "${local.s3_arn}${b}"]
  }

  statement {
    sid       = "DataKeys"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:DescribeKey"]
    resources = distinct(concat(var.data_kms_key_arns, [var.s3_kms_key_arn]))
  }

  statement {
    sid       = "LogsKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.logs_kms_key_arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:AssociateKmsKey"]
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws-glue/*"]
  }

  # UpdateTable also writes the lineage table properties of each refresh (data/README.md).
  statement {
    sid = "Catalog"
    actions = [
      "glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:CreateTable", "glue:UpdateTable",
      "glue:DeleteTable", "glue:GetPartition", "glue:GetPartitions", "glue:CreatePartition", "glue:UpdatePartition",
      "glue:BatchCreatePartition", "glue:BatchGetPartition", "glue:BatchDeletePartition", "glue:DeletePartition",
    ]
    resources = concat(
      ["${local.glue_arn}:catalog"],
      [for d in local.databases : "${local.glue_arn}:database/${d}"],
      [for d in local.databases : "${local.glue_arn}:table/${d}/*"],
    )
  }

  statement {
    sid       = "Connection"
    actions   = ["glue:GetConnection"]
    resources = ["${local.glue_arn}:catalog", "${local.glue_arn}:connection/${local.connection}"]
  }

  statement {
    sid       = "DataQuality"
    actions   = ["glue:GetDataQualityRuleset", "glue:PublishDataQuality"]
    resources = ["${local.glue_arn}:dataQualityRuleset/${local.ruleset}"]
  }

  statement {
    sid       = "JobMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Glue", "AWS/Glue/DataQuality"]
    }
  }

  statement {
    sid = "ConnectionNetwork"
    actions = [
      "ec2:DescribeVpcEndpoints", "ec2:DescribeRouteTables", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets", "ec2:DescribeVpcAttribute", "ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ConnectionNetworkTags"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["aws-glue-service-resource"]
    }
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "glue-jobs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

# ------------------------------------------------------------------ Seed scripts (glue.yml owns the content afterwards)
resource "aws_s3_object" "seed_script" {
  for_each = local.jobs

  bucket       = var.assets_bucket_name
  key          = "scripts/${each.key}.py"
  content      = local.seed_script
  content_type = "text/x-python"
  kms_key_id   = var.s3_kms_key_arn

  tags = local.tags

  lifecycle {
    ignore_changes = [content, etag, source_hash, kms_key_id, metadata, tags, tags_all]
  }
}

# ------------------------------------------------------------------ Jobs
resource "aws_glue_job" "this" {
  for_each = local.jobs

  name                   = "${var.name_prefix}-glue-${each.key}"
  description            = each.value.description
  role_arn               = aws_iam_role.this.arn
  glue_version           = var.glue_version
  worker_type            = var.worker_type
  number_of_workers      = var.number_of_workers
  timeout                = var.timeout_minutes
  max_retries            = 0
  security_configuration = aws_glue_security_configuration.this.name
  connections            = [aws_glue_connection.vpc.name]

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.assets_bucket_name}/${aws_s3_object.seed_script[each.key].key}"
  }

  execution_property {
    max_concurrent_runs = max(length(var.business_units), 1)
  }

  default_arguments = merge(
    local.common_arguments,
    {
      "--TempDir"             = "s3://${var.assets_bucket_name}/temp/${each.key}/"
      "--job-bookmark-option" = each.value.bookmarks ? "job-bookmark-enable" : "job-bookmark-disable"
    },
    lookup(local.job_arguments, each.key, {}),
    lookup(var.extra_job_arguments, each.key, {}),
  )

  tags = merge(local.tags, { Name = "${var.name_prefix}-glue-${each.key}" })

  depends_on = [aws_iam_role_policy.this, aws_cloudwatch_log_group.this]
}

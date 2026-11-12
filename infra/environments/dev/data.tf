# ================================================================== Step 13 - Data platform (Glue lakehouse) and model refresh
# v4: Databricks is only the source catalog. Per business unit the model-refresh state machine
#   1. starts the WBD Databricks export job through the export Lambda (Jobs API) - raw Parquet lands
#      in landing raw/databricks/<bu>/<refresh_id>/ (Unity Catalog role: write there only),
#   2. runs the Glue medallion: Bronze (ingested raw) -> Silver (cleansed, Data Quality) -> Gold
#      (per-BU modeling tables, adstock and saturation), Delta Lake on the lakehouse bucket,
#   3. Glue exports: Gold -> immutable Parquet training snapshot, Gold -> RDS PostgreSQL (in parallel),
#   4. SageMaker trains and evaluates (baseline -> channel lift -> title adjustment inside the image),
#      registers the model package as PendingManualApproval (approved by WBD in model-governance.yml),
#   5. the results-publisher Lambda writes predictions, lift and evaluation results to RDS.
# Orchestration: EventBridge Scheduler / "mmm.refresh" event -> model-refresh state machine.
# Drift: a daily model-monitor state machine per BU runs the same export + medallion, Glue
# export-monitor writes the latest features and SageMaker compares them with the approved baseline.
# DevOps owns the plumbing; job and model code belong to the data team. Everything in this file
# exists only when enable_data_platform = true.
locals {
  data_platform_kms_purposes = var.enable_data_platform ? [for bu in var.business_units : "s3-${bu}"] : []
  bu_key_arns                = var.enable_data_platform ? { for bu in var.business_units : bu => module.kms.key_arns["s3-${bu}"] } : {}

  data_count = var.enable_data_platform ? 1 : 0

  # Built from the name: the landing bucket policy can't reference the bucket module's own output.
  landing_bucket_name = "wbd-mmm-${local.env_short}-landing-${local.region_code}"
  landing_bucket_arn  = "arn:${local.partition}:s3:::${local.landing_bucket_name}"
  raw_export_prefix   = "raw/databricks/"

  data_key_arns = concat([module.kms.key_arns["s3"]], values(local.bu_key_arns))

  refresh_name         = "model-refresh"
  monitor_name         = "model-monitor"
  training_job_prefix  = "${local.name_prefix}-train"
  evaluate_job_prefix  = "${local.name_prefix}-eval"
  drift_job_prefix     = "${local.name_prefix}-drift"
  sagemaker_arn_prefix = "arn:${local.partition}:sagemaker:${var.aws_region}:${local.account_id}"

  # Silver data-quality rules belong to the data engineers; the default only checks the table is not empty.
  silver_ruleset_file = "${path.module}/../../../data/glue/dq/silver.dqdl"
}

# Files under landing/<bu>/ and raw/databricks/<bu>/ must be encrypted with that business unit's key.
data "aws_iam_policy_document" "landing_bu_keys" {
  dynamic "statement" {
    for_each = local.bu_key_arns
    content {
      sid       = "RequireKeyOf${replace(title(statement.key), "-", "")}"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.landing_bucket_arn}/${statement.key}/*", "${local.landing_bucket_arn}/${local.raw_export_prefix}${statement.key}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [statement.value]
      }
    }
  }
}

# ------------------------------------------------------------------ Databricks: Unity Catalog role (export target only), PrivateLink, private DNS
module "databricks_access" {
  source = "../../modules/databricks-access"
  count  = local.data_count

  name_prefix           = local.name_prefix
  databricks_account_id = var.databricks_account_id
  self_assume_enabled   = var.databricks_self_assume_enabled

  # The WBD export job writes the raw extract here and nowhere else in this account.
  write_prefixes = [{ bucket_arn = module.buckets["landing"].bucket_arn, prefix = local.raw_export_prefix }]
  kms_key_arns   = local.data_key_arns

  enable_privatelink         = var.enable_databricks_privatelink
  workspace_host             = var.databricks_host
  workspace_service_name     = var.databricks_privatelink_service_name
  vpc_id                     = module.network.vpc_id
  endpoint_subnet_ids        = module.network.private_endpoint_subnet_ids
  endpoint_security_group_id = module.network.security_group_ids["endpoints"]

  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Databricks export Lambda (Jobs API run-now / runs get)
module "databricks_export" {
  source = "../../modules/databricks-export"
  count  = local.data_count

  name_prefix                  = local.name_prefix
  databricks_host              = var.databricks_host
  service_principal_secret_arn = module.secrets.secret_arns["databricks/export-sp"]
  job_ids_parameter_name       = module.secrets.parameter_names["databricks/export_job_ids"]
  job_ids_parameter_arn        = module.secrets.parameter_arns["databricks/export_job_ids"]

  landing_bucket_arn = module.buckets["landing"].bucket_arn
  manifest_prefix    = local.raw_export_prefix
  business_unit_keys = local.bu_key_arns
  default_key_arn    = module.kms.key_arns["s3"]

  secrets_kms_key_arn = module.kms.key_arns["secrets"]
  logs_kms_key_arn    = module.kms.key_arns["logs"]
  log_retention_days  = var.log_retention_days

  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.network.security_group_ids["databricks_export"]]

  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ AWS Glue: catalog, jobs, data quality
data "aws_subnet" "glue" {
  count = local.data_count
  id    = module.network.private_app_subnet_ids[0]
}

module "glue" {
  source = "../../modules/glue"
  count  = local.data_count

  name_prefix    = local.name_prefix
  environment    = var.environment
  business_units = var.business_units

  assets_bucket_name        = module.buckets["glue-assets"].bucket_name
  landing_bucket_name       = module.buckets["landing"].bucket_name
  lakehouse_bucket_name     = module.buckets["lakehouse"].bucket_name
  training_data_bucket_name = module.buckets["training-data"].bucket_name
  data_kms_key_arns         = local.data_key_arns
  s3_kms_key_arn            = module.kms.key_arns["s3"]
  logs_kms_key_arn          = module.kms.key_arns["logs"]
  log_retention_days        = var.log_retention_days

  glue_version              = var.glue_version
  worker_type               = var.glue_worker_type
  number_of_workers         = var.glue_number_of_workers
  timeout_minutes           = var.glue_job_timeout_minutes
  silver_ruleset            = fileexists(local.silver_ruleset_file) ? file(local.silver_ruleset_file) : "Rules = [ RowCount > 0 ]"
  manage_catalog_encryption = var.manage_glue_catalog_encryption

  subnet_id          = module.network.private_app_subnet_ids[0]
  availability_zone  = data.aws_subnet.glue[0].availability_zone
  security_group_ids = [module.network.security_group_ids["glue"], module.network.security_group_ids["data_clients"]]

  db_host     = module.rds.proxy_endpoint
  db_name     = module.rds.db_name
  db_user     = "mmm_etl"
  db_user_arn = "${local.proxy_dbuser_arn}/mmm_etl"

  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Training execution role + model registry
module "sagemaker_training" {
  source = "../../modules/sagemaker"
  count  = local.data_count

  name_prefix         = local.name_prefix
  name                = "training"
  read_bucket_arns    = [module.buckets["training-data"].bucket_arn, module.buckets["models"].bucket_arn, module.buckets["lakehouse"].bucket_arn]
  write_bucket_arns   = [module.buckets["models"].bucket_arn]
  data_kms_key_arns   = local.data_key_arns
  volume_kms_key_arn  = module.kms.key_arns["sagemaker"]
  ecr_repository_arns = ["${local.ecr_repo_arn_prefix}/mmm/sagemaker-training"]

  # One model package group per business unit: <name_prefix>-<bu>
  model_package_groups   = var.business_units
  notification_topic_arn = module.monitoring.alert_topic_arn

  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Shared state builders
locals {
  snapshot_uri   = "States.Format('s3://wbd-mmm-${local.env_short}-training-data-${local.region_code}/{}/{}/', $.business_unit, $.refresh_id)"
  evaluation_uri = "States.Format('s3://wbd-mmm-${local.env_short}-models-${local.region_code}/evaluation/{}/{}/', $.business_unit, $.refresh_id)"
  raw_uri        = "States.Format('s3://${local.landing_bucket_name}/${local.raw_export_prefix}{}/{}/', $.business_unit, $.refresh_id)"

  sagemaker_vpc = {
    Subnets          = module.network.private_app_subnet_ids
    SecurityGroupIds = [module.network.security_group_ids["sagemaker"]]
  }

  lambda_retry = [
    { ErrorEquals = ["DatabricksRetryable"], IntervalSeconds = 30, MaxAttempts = 4, BackoffRate = 2 },
    { ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"], IntervalSeconds = 5, MaxAttempts = 3, BackoffRate = 2 },
  ]

  glue_retry = [{
    ErrorEquals     = ["Glue.ConcurrentRunsExceededException", "Glue.ThrottlingException", "Glue.InternalServiceException"]
    IntervalSeconds = 60
    MaxAttempts     = 3
    BackoffRate     = 2
  }]

  export_function_arn = var.enable_data_platform ? module.databricks_export[0].function_arn : ""
  glue_jobs           = var.enable_data_platform ? module.glue[0].job_names : {}

  monitor_raw_uri = "States.Format('s3://${local.landing_bucket_name}/${local.raw_export_prefix}{}/monitor-{}/', $.business_unit, $.monitor_id)"

  # Export via the Databricks Jobs API: start, then poll every minute until the run is terminal.
  # p = state-name prefix; request_id = refresh_id | monitor_id (idempotency token of run-now).
  # Values are JSON (the state sets have different keys); jsondecode() where they are used.
  export_states = { for purpose, cfg in {
    refresh = { p = "", id = "$.refresh_id", next = "Bronze", uri = local.raw_uri }
    monitor = { p = "Monitor", id = "$.monitor_id", next = "MonitorBronze", uri = local.monitor_raw_uri }
    } : purpose => jsonencode({
      "${cfg.p}StartExport" = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.export_function_arn
          Payload = {
            action            = "start"
            purpose           = purpose
            "business_unit.$" = "$.business_unit"
            "output_uri.$"    = cfg.uri
            "request_id.$"    = cfg.id
          }
        }
        ResultSelector = { "run_id.$" = "$.Payload.run_id" }
        ResultPath     = "$.export"
        Retry          = local.lambda_retry
        Next           = "${cfg.p}WaitForExport"
      }
      "${cfg.p}WaitForExport" = { Type = "Wait", Seconds = 60, Next = "${cfg.p}GetExportStatus" }
      "${cfg.p}GetExportStatus" = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::lambda:invoke"
        Parameters = {
          FunctionName = local.export_function_arn
          Payload = {
            action            = "status"
            "run_id.$"        = "$.export.run_id"
            "business_unit.$" = "$.business_unit"
            "output_uri.$"    = cfg.uri
          }
        }
        ResultSelector = { "status.$" = "$.Payload" }
        ResultPath     = "$.export.run"
        Retry          = local.lambda_retry
        Next           = "${cfg.p}ExportDone"
      }
      "${cfg.p}ExportDone" = {
        Type = "Choice"
        Choices = [
          { Variable = "$.export.run.status.succeeded", BooleanEquals = true, Next = cfg.next },
          { Variable = "$.export.run.status.done", BooleanEquals = true, Next = "${cfg.p}ExportFailed" },
        ]
        Default = "${cfg.p}WaitForExport"
      }
      "${cfg.p}ExportFailed" = { Type = "Fail", Error = "DatabricksExportFailed", Cause = "The Databricks export job did not succeed; see the export Lambda log and the run in the Databricks workspace (runbooks/databricks-export-failed.md)." }
  }) }

  # One Glue job run (.sync) per state; arguments are the per-run values, the job has the rest (JSON, as above).
  glue_step = { for k, cfg in {
    Bronze                = { job = "bronze", next = "Silver", monitor = false, args = { "--raw_uri.$" = local.raw_uri } }
    Silver                = { job = "silver", next = "Gold", monitor = false, args = {} }
    Gold                  = { job = "gold", next = "GlueExports", monitor = false, args = {} }
    ExportTraining        = { job = "export-training", next = null, monitor = false, args = { "--snapshot_uri.$" = local.snapshot_uri } }
    ExportRds             = { job = "export-rds", next = null, monitor = false, args = {} }
    MonitorBronze         = { job = "bronze", next = "MonitorSilver", monitor = true, args = { "--raw_uri.$" = local.monitor_raw_uri } }
    MonitorSilver         = { job = "silver", next = "MonitorGold", monitor = true, args = {} }
    MonitorGold           = { job = "gold", next = "ExportMonitorFeatures", monitor = true, args = {} }
    ExportMonitorFeatures = { job = "export-monitor", next = "GetTrainingImage", monitor = true, args = { "--monitor_uri.$" = local.features_uri } }
    } : k => jsonencode(merge(
      {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = lookup(local.glue_jobs, cfg.job, "")
          Arguments = merge({
            "--business_unit.$" = "$.business_unit"
            "--run_id.$"        = cfg.monitor ? "$.monitor_id" : "$.refresh_id"
            "--purpose"         = cfg.monitor ? "monitor" : "refresh"
          }, cfg.args)
        }
        ResultSelector = { "run_id.$" = "$.Id", "state.$" = "$.JobRunState" }
        ResultPath     = "$.glue.${replace(cfg.job, "-", "_")}"
        Retry          = local.glue_retry
      },
      jsondecode(cfg.next == null ? jsonencode({ End = true }) : jsonencode({ Next = cfg.next })),
  )) }
}

# ------------------------------------------------------------------ Model-refresh state machine
locals {
  refresh_definition = var.enable_data_platform ? {
    Comment        = "MMM model refresh per business unit (${var.environment})"
    StartAt        = "Init"
    TimeoutSeconds = 8 * 3600
    States = merge(
      {
        # refresh_id names the raw export, snapshot, jobs and evaluation (SageMaker job names: max 63 characters)
        Init = {
          Type       = "Pass"
          Parameters = { "business_unit.$" = "$.business_unit", "refresh_id.$" = "States.UUID()" }
          Next       = "GetTrainingImage"
        }
        GetTrainingImage = {
          Type           = "Task"
          Resource       = "arn:${local.partition}:states:::aws-sdk:ssm:getParameter"
          Parameters     = { Name = aws_ssm_parameter.sagemaker_image["training"].name }
          ResultSelector = { "uri.$" = "$.Parameter.Value" }
          ResultPath     = "$.image"
          Next           = "StartExport"
        }
      },
      jsondecode(local.export_states["refresh"]),
      {
        Bronze = jsondecode(local.glue_step["Bronze"])
        Silver = jsondecode(local.glue_step["Silver"])
        Gold   = jsondecode(local.glue_step["Gold"])
        # Glue exports: training snapshot and RDS reference tables at the same time
        GlueExports = {
          Type = "Parallel"
          Branches = [
            { StartAt = "ExportTraining", States = { ExportTraining = jsondecode(local.glue_step["ExportTraining"]) } },
            { StartAt = "ExportRds", States = { ExportRds = jsondecode(local.glue_step["ExportRds"]) } },
          ]
          ResultPath = null
          Next       = "TrainModel"
        }
        TrainModel = {
          Type     = "Task"
          Resource = "arn:${local.partition}:states:::sagemaker:createTrainingJob.sync"
          Parameters = {
            "TrainingJobName.$"    = "States.Format('${local.training_job_prefix}-{}', $.refresh_id)"
            RoleArn                = module.sagemaker_training[0].role_arn
            AlgorithmSpecification = { "TrainingImage.$" = "$.image.uri", TrainingInputMode = "File" }
            Environment            = { APP_ENV = var.environment, "BUSINESS_UNIT.$" = "$.business_unit" }
            InputDataConfig = [{
              ChannelName = "train"
              DataSource  = { S3DataSource = { S3DataType = "S3Prefix", "S3Uri.$" = local.snapshot_uri, S3DataDistributionType = "FullyReplicated" } }
            }]
            OutputDataConfig = {
              "S3OutputPath.$" = "States.Format('s3://wbd-mmm-${local.env_short}-models-${local.region_code}/artifacts/{}/', $.business_unit)"
              KmsKeyId         = module.kms.key_arns["s3"]
            }
            ResourceConfig = {
              InstanceCount  = 1
              InstanceType   = var.training_instance_type
              VolumeSizeInGB = 50
              VolumeKmsKeyId = module.kms.key_arns["sagemaker"]
            }
            StoppingCondition                     = { MaxRuntimeInSeconds = var.training_max_runtime_seconds }
            VpcConfig                             = local.sagemaker_vpc
            EnableInterContainerTrafficEncryption = true
            Tags                                  = [{ Key = "business_unit", "Value.$" = "$.business_unit" }]
          }
          ResultSelector = { "name.$" = "$.TrainingJobName", "artifact.$" = "$.ModelArtifacts.S3ModelArtifacts" }
          ResultPath     = "$.training"
          Next           = "EvaluateModel"
        }
        # Same image, argument "evaluate": baseline -> channel lift -> title adjustment; writes
        # evaluation.json (metrics), predictions/ and lift/ next to the hold-out results.
        EvaluateModel = {
          Type     = "Task"
          Resource = "arn:${local.partition}:states:::sagemaker:createProcessingJob.sync"
          Parameters = {
            "ProcessingJobName.$" = "States.Format('${local.evaluate_job_prefix}-{}', $.refresh_id)"
            RoleArn               = module.sagemaker_training[0].role_arn
            AppSpecification      = { "ImageUri.$" = "$.image.uri", ContainerArguments = ["evaluate"] }
            Environment           = { APP_ENV = var.environment, "BUSINESS_UNIT.$" = "$.business_unit" }
            ProcessingResources = {
              ClusterConfig = {
                InstanceCount  = 1
                InstanceType   = var.evaluation_instance_type
                VolumeSizeInGB = 30
                VolumeKmsKeyId = module.kms.key_arns["sagemaker"]
              }
            }
            ProcessingInputs = [
              { InputName = "model", S3Input = { "S3Uri.$" = "$.training.artifact", LocalPath = "/opt/ml/processing/model", S3DataType = "S3Prefix", S3InputMode = "File" } },
              { InputName = "data", S3Input = { "S3Uri.$" = local.snapshot_uri, LocalPath = "/opt/ml/processing/data", S3DataType = "S3Prefix", S3InputMode = "File" } },
            ]
            ProcessingOutputConfig = {
              KmsKeyId = module.kms.key_arns["s3"]
              Outputs  = [{ OutputName = "evaluation", S3Output = { "S3Uri.$" = local.evaluation_uri, LocalPath = "/opt/ml/processing/evaluation", S3UploadMode = "EndOfJob" } }]
            }
            StoppingCondition = { MaxRuntimeInSeconds = var.evaluation_max_runtime_seconds }
            NetworkConfig     = { EnableInterContainerTrafficEncryption = true, VpcConfig = local.sagemaker_vpc }
          }
          ResultPath = null
          Next       = "RegisterModel"
        }
        RegisterModel = {
          Type     = "Task"
          Resource = "arn:${local.partition}:states:::aws-sdk:sagemaker:createModelPackage"
          Parameters = {
            "ModelPackageGroupName.$"   = "States.Format('${local.name_prefix}-{}', $.business_unit)"
            ModelApprovalStatus         = "PendingManualApproval"
            "ModelPackageDescription.$" = "States.Format('Refresh {} (training job {})', $.refresh_id, $.training.name)"
            InferenceSpecification = {
              Containers                 = [{ "Image.$" = "$.image.uri", "ModelDataUrl.$" = "$.training.artifact" }]
              SupportedContentTypes      = ["application/json"]
              SupportedResponseMIMETypes = ["application/json"]
            }
            ModelMetrics = {
              ModelQuality = {
                Statistics = { ContentType = "application/json", "S3Uri.$" = "States.Format('{}evaluation.json', ${local.evaluation_uri})" }
              }
            }
            CustomerMetadataProperties = {
              "training_job.$"      = "$.training.name"
              "databricks_run_id.$" = "States.Format('{}', $.export.run_id)"
              "refresh_id.$"        = "$.refresh_id"
            }
          }
          ResultSelector = { "model_package_arn.$" = "$.ModelPackageArn" }
          ResultPath     = "$.registered"
          Next           = "PublishModelResults"
        }
        # Results publisher: model predictions, lift and evaluation results -> RDS for this dataset
        # (tagged with model_package_arn; the approval status lives in the registry).
        PublishModelResults = {
          Type     = "Task"
          Resource = "arn:${local.partition}:states:::lambda:invoke"
          Parameters = {
            FunctionName = module.publisher.alias_arn
            Payload = {
              event                 = "model_results"
              "business_unit.$"     = "$.business_unit"
              "refresh_id.$"        = "$.refresh_id"
              "model_package_arn.$" = "$.registered.model_package_arn"
              "evaluation_uri.$"    = local.evaluation_uri
            }
          }
          ResultPath = null
          Retry      = slice(local.lambda_retry, 1, 2)
          Next       = "RefreshComplete"
        }
        RefreshComplete = { Type = "Succeed" }
      },
    )
  } : null
}

data "aws_iam_policy_document" "refresh_sfn" {
  count = local.data_count

  statement {
    sid       = "ReadImagePointer"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sagemaker_image["training"].arn]
  }

  statement {
    sid       = "InvokeLambdas"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.databricks_export[0].function_arn, module.publisher.alias_arn]
  }

  statement {
    sid       = "RunGlueJobs"
    actions   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
    resources = [for k in ["bronze", "silver", "gold", "export-training", "export-rds"] : module.glue[0].job_arns[k]]
  }

  statement {
    sid     = "RunJobs"
    actions = ["sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:StopTrainingJob", "sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:AddTags", "sagemaker:ListTags"]
    resources = [
      "${local.sagemaker_arn_prefix}:training-job/${local.training_job_prefix}-*",
      "${local.sagemaker_arn_prefix}:processing-job/${local.evaluate_job_prefix}-*",
    ]
  }

  statement {
    sid       = "RegisterModel"
    actions   = ["sagemaker:CreateModelPackage", "sagemaker:AddTags"]
    resources = ["${local.sagemaker_arn_prefix}:model-package-group/${local.name_prefix}-*", "${local.sagemaker_arn_prefix}:model-package/${local.name_prefix}-*/*"]
  }

  statement {
    sid     = "SyncRules"
    actions = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = [
      "arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/StepFunctionsGetEventsForSageMakerTrainingJobsRule",
      "arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/StepFunctionsGetEventsForSageMakerProcessingJobsRule",
    ]
  }

  statement {
    sid       = "PassJobRole"
    actions   = ["iam:PassRole"]
    resources = [module.sagemaker_training[0].role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }

  statement {
    sid       = "JobKeys"
    actions   = ["kms:CreateGrant", "kms:DescribeKey"]
    resources = [module.kms.key_arns["sagemaker"], module.kms.key_arns["s3"]]
  }
}

module "refresh_sfn" {
  source = "../../modules/step-functions"
  count  = local.data_count

  name_prefix            = local.name_prefix
  name                   = local.refresh_name
  definition             = jsonencode(local.refresh_definition)
  role_policy_json       = data.aws_iam_policy_document.refresh_sfn[0].json
  include_execution_data = !local.is_prod
  component              = "model-refresh"

  logs_kms_key_arn         = module.kms.key_arns["logs"]
  log_retention_days       = var.log_retention_days
  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Triggers: schedule per BU and on-demand event
data "aws_iam_policy_document" "refresh_trigger_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com", "events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "refresh_trigger" {
  count = local.data_count

  name                 = "${local.name_prefix}-model-refresh-trigger"
  description          = "EventBridge Scheduler / rule -> start the model-refresh and model-monitor state machines"
  assume_role_policy   = data.aws_iam_policy_document.refresh_trigger_trust.json
  permissions_boundary = module.permission_boundary.policy_arn

  tags = merge(local.tags, { Component = "model-refresh" })
}

resource "aws_iam_role_policy" "refresh_trigger" {
  count = local.data_count

  name = "start-model-refresh"
  role = aws_iam_role.refresh_trigger[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "StartRefreshAndMonitor", Effect = "Allow", Action = "states:StartExecution", Resource = [module.refresh_sfn[0].state_machine_arn, module.monitor_sfn[0].state_machine_arn] }]
  })
}

resource "aws_scheduler_schedule_group" "refresh" {
  count = local.data_count

  name = "${local.name_prefix}-model-refresh"
  tags = merge(local.tags, { Component = "model-refresh" })
}

resource "aws_scheduler_schedule" "refresh" {
  #checkov:skip=CKV_AWS_297:The schedule input is only the business-unit name; nothing sensitive to encrypt with a CMK.
  for_each = var.enable_data_platform ? toset(var.business_units) : toset([])

  name                         = "${local.name_prefix}-refresh-${each.key}"
  group_name                   = aws_scheduler_schedule_group.refresh[0].name
  description                  = "Scheduled model refresh for ${each.key}"
  schedule_expression          = var.model_refresh_schedule
  schedule_expression_timezone = var.model_refresh_timezone
  state                        = var.enable_model_refresh_schedule ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.refresh_sfn[0].state_machine_arn
    role_arn = aws_iam_role.refresh_trigger[0].arn
    input    = jsonencode({ business_unit = each.key })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}

# On demand (manual or from the app): scripts/trigger-model-refresh.sh, the data team or the API puts
#   {"source": "mmm.refresh", "detail-type": "Model Refresh Requested", "detail": {"business_unit": "<bu>"}}
resource "aws_cloudwatch_event_rule" "refresh_on_demand" {
  count = local.data_count

  name        = "${local.name_prefix}-model-refresh-on-demand"
  description = "Start a model refresh for one business unit"
  event_pattern = jsonencode({
    source        = ["mmm.refresh"]
    "detail-type" = ["Model Refresh Requested"]
    detail        = { business_unit = var.business_units }
  })

  tags = merge(local.tags, { Component = "model-refresh" })
}

resource "aws_cloudwatch_event_target" "refresh_on_demand" {
  count = local.data_count

  rule      = aws_cloudwatch_event_rule.refresh_on_demand[0].name
  target_id = "model-refresh"
  arn       = module.refresh_sfn[0].state_machine_arn
  role_arn  = aws_iam_role.refresh_trigger[0].arn

  input_transformer {
    input_paths    = { bu = "$.detail.business_unit" }
    input_template = "{\"business_unit\": <bu>}"
  }
}

# ------------------------------------------------------------------ Model-monitor (drift) state machine
# Per BU, daily: Databricks export (purpose monitor) -> Glue Bronze / Silver / Gold -> Glue
# export-monitor writes the latest features -> SageMaker Processing (training image, argument
# "drift") compares them with the approved baseline (models/baseline/<bu>/, written by
# model-governance on approval) -> drift.json -> metric ModelDrift -> alarm above the threshold;
# with auto_refresh_on_drift the state machine also requests a model refresh.
locals {
  # Per-BU drift threshold from data/model-thresholds.yaml (business_units.<bu>.drift.threshold), else the default
  model_thresholds = yamldecode(file("${path.module}/../../../data/model-thresholds.yaml"))
  drift_threshold  = { for bu in var.business_units : bu => try(tonumber(local.model_thresholds.business_units[bu].drift.threshold), var.model_drift_threshold) }

  models_bucket_name = "wbd-mmm-${local.env_short}-models-${local.region_code}"
  monitor_date       = "States.ArrayGetItem(States.StringSplit($$.Execution.StartTime, 'T'), 0)"
  features_uri       = "States.Format('s3://wbd-mmm-${local.env_short}-lakehouse-${local.region_code}/monitoring/{}/{}/', $.business_unit, $.monitor_date)"
  drift_output_uri   = "States.Format('s3://${local.models_bucket_name}/monitoring/{}/{}/', $.business_unit, $.monitor_date)"

  monitor_states = var.enable_data_platform ? merge(
    {
      ApplyDefaults = {
        Type       = "Pass"
        Parameters = { "args.$" = "States.JsonMerge(States.StringToJson('{\"drift_threshold\":${var.model_drift_threshold},\"auto_refresh\":${var.auto_refresh_on_drift}}'), $, false)" }
        OutputPath = "$.args"
        Next       = "Init"
      }
      Init = {
        Type = "Pass"
        Parameters = {
          "business_unit.$"   = "$.business_unit"
          "drift_threshold.$" = "$.drift_threshold"
          "auto_refresh.$"    = "$.auto_refresh"
          "monitor_id.$"      = "States.UUID()"
          "monitor_date.$"    = local.monitor_date
        }
        Next = "MonitorStartExport"
      }
    },
    jsondecode(local.export_states["monitor"]),
    {
      MonitorBronze         = jsondecode(local.glue_step["MonitorBronze"])
      MonitorSilver         = jsondecode(local.glue_step["MonitorSilver"])
      MonitorGold           = jsondecode(local.glue_step["MonitorGold"])
      ExportMonitorFeatures = jsondecode(local.glue_step["ExportMonitorFeatures"])
      GetTrainingImage = {
        Type           = "Task"
        Resource       = "arn:${local.partition}:states:::aws-sdk:ssm:getParameter"
        Parameters     = { Name = aws_ssm_parameter.sagemaker_image["training"].name }
        ResultSelector = { "uri.$" = "$.Parameter.Value" }
        ResultPath     = "$.image"
        Next           = "CheckDrift"
      }
      # Training image, argument "drift": writes drift.json {"score": 0-1, "checks": {...}}
      CheckDrift = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::sagemaker:createProcessingJob.sync"
        Parameters = {
          "ProcessingJobName.$" = "States.Format('${local.drift_job_prefix}-{}', $.monitor_id)"
          RoleArn               = module.sagemaker_training[0].role_arn
          AppSpecification      = { "ImageUri.$" = "$.image.uri", ContainerArguments = ["drift"] }
          Environment = {
            APP_ENV             = var.environment
            "BUSINESS_UNIT.$"   = "$.business_unit"
            "DRIFT_THRESHOLD.$" = "States.Format('{}', $.drift_threshold)"
          }
          ProcessingResources = {
            ClusterConfig = {
              InstanceCount  = 1
              InstanceType   = var.evaluation_instance_type
              VolumeSizeInGB = 30
              VolumeKmsKeyId = module.kms.key_arns["sagemaker"]
            }
          }
          ProcessingInputs = [
            { InputName = "baseline", S3Input = { "S3Uri.$" = "States.Format('s3://${local.models_bucket_name}/baseline/{}/', $.business_unit)", LocalPath = "/opt/ml/processing/baseline", S3DataType = "S3Prefix", S3InputMode = "File" } },
            { InputName = "curves", S3Input = { "S3Uri.$" = "States.Format('s3://${local.models_bucket_name}/curves/{}/', $.business_unit)", LocalPath = "/opt/ml/processing/curves", S3DataType = "S3Prefix", S3InputMode = "File" } },
            { InputName = "features", S3Input = { "S3Uri.$" = local.features_uri, LocalPath = "/opt/ml/processing/features", S3DataType = "S3Prefix", S3InputMode = "File" } },
          ]
          ProcessingOutputConfig = {
            KmsKeyId = module.kms.key_arns["s3"]
            Outputs  = [{ OutputName = "drift", S3Output = { "S3Uri.$" = local.drift_output_uri, LocalPath = "/opt/ml/processing/drift", S3UploadMode = "EndOfJob" } }]
          }
          StoppingCondition = { MaxRuntimeInSeconds = var.evaluation_max_runtime_seconds }
          NetworkConfig     = { EnableInterContainerTrafficEncryption = true, VpcConfig = local.sagemaker_vpc }
          Tags              = [{ Key = "business_unit", "Value.$" = "$.business_unit" }]
        }
        ResultPath = null
        Next       = "ReadDrift"
      }
      ReadDrift = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::aws-sdk:s3:getObject"
        Parameters = {
          Bucket  = local.models_bucket_name
          "Key.$" = "States.Format('monitoring/{}/{}/drift.json', $.business_unit, $.monitor_date)"
        }
        ResultSelector = { "result.$" = "States.StringToJson($.Body)" }
        ResultPath     = "$.drift"
        Next           = "PublishDrift"
      }
      PublishDrift = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::aws-sdk:cloudwatch:putMetricData"
        Parameters = {
          Namespace = "MMM/Models"
          MetricData = [{
            MetricName = "ModelDrift"
            Dimensions = [{ Name = "BusinessUnit", "Value.$" = "$.business_unit" }, { Name = "Check", Value = "overall" }]
            "Value.$"  = "$.drift.result.score"
          }]
        }
        ResultPath = null
        Next       = "DriftDecision"
      }
      DriftDecision = {
        Type = "Choice"
        Choices = [
          {
            And = [
              { Variable = "$.drift.result.score", NumericGreaterThanPath = "$.drift_threshold" },
              { Variable = "$.auto_refresh", BooleanEquals = true },
            ]
            Next = "BuildRefreshRequest"
          },
          { Variable = "$.drift.result.score", NumericGreaterThanPath = "$.drift_threshold", Next = "DriftDetected" },
        ]
        Default = "NoDrift"
      }
      NoDrift       = { Type = "Succeed" }
      DriftDetected = { Type = "Succeed", Comment = "Drift above the threshold: alarm model-drift-<bu> fires; a person decides on a refresh (runbooks/model-drift.md)." }
      BuildRefreshRequest = {
        Type       = "Pass"
        Parameters = { "business_unit.$" = "$.business_unit", reason = "drift", "monitor_date.$" = "$.monitor_date" }
        ResultPath = "$.refresh_request"
        Next       = "RequestRefresh"
      }
      # Same event as scripts/trigger-model-refresh.sh -> rule <prefix>-model-refresh-on-demand
      RequestRefresh = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::aws-sdk:eventbridge:putEvents"
        Parameters = {
          Entries = [{
            Source       = "mmm.refresh"
            DetailType   = "Model Refresh Requested"
            "Detail.$"   = "States.JsonToString($.refresh_request)"
            EventBusName = "default"
          }]
        }
        ResultPath = null
        End        = true
      }
    },
  ) : null
}

data "aws_iam_policy_document" "monitor_sfn" {
  count = local.data_count

  statement {
    sid       = "ReadImagePointer"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sagemaker_image["training"].arn]
  }

  statement {
    sid       = "InvokeExport"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.databricks_export[0].function_arn]
  }

  statement {
    sid       = "RunGlueJobs"
    actions   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
    resources = [for k in ["bronze", "silver", "gold", "export-monitor"] : module.glue[0].job_arns[k]]
  }

  statement {
    sid       = "RunDriftJob"
    actions   = ["sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:AddTags", "sagemaker:ListTags"]
    resources = ["${local.sagemaker_arn_prefix}:processing-job/${local.drift_job_prefix}-*"]
  }

  statement {
    sid       = "SyncRule"
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/StepFunctionsGetEventsForSageMakerProcessingJobsRule"]
  }

  statement {
    sid       = "PassJobRole"
    actions   = ["iam:PassRole"]
    resources = [module.sagemaker_training[0].role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }

  statement {
    sid       = "JobKeys"
    actions   = ["kms:CreateGrant", "kms:DescribeKey"]
    resources = [module.kms.key_arns["sagemaker"], module.kms.key_arns["s3"]]
  }

  statement {
    sid       = "ReadDriftResult"
    actions   = ["s3:GetObject"]
    resources = ["${module.buckets["models"].bucket_arn}/monitoring/*"]
  }

  statement {
    sid       = "DriftResultKey"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.key_arns["s3"]]
  }

  statement {
    sid       = "PublishDrift"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["MMM/Models"]
    }
  }

  # Used only when auto_refresh is true (auto_refresh_on_drift or an on-demand input)
  statement {
    sid       = "RequestRefresh"
    actions   = ["events:PutEvents"]
    resources = ["arn:${local.partition}:events:${var.aws_region}:${local.account_id}:event-bus/default"]
  }
}

module "monitor_sfn" {
  source = "../../modules/step-functions"
  count  = local.data_count

  name_prefix            = local.name_prefix
  name                   = local.monitor_name
  definition             = jsonencode({ Comment = "MMM model drift check per business unit (${var.environment})", StartAt = "ApplyDefaults", TimeoutSeconds = 6 * 3600, States = local.monitor_states })
  role_policy_json       = data.aws_iam_policy_document.monitor_sfn[0].json
  include_execution_data = !local.is_prod
  component              = "model-refresh"

  logs_kms_key_arn         = module.kms.key_arns["logs"]
  log_retention_days       = var.log_retention_days
  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

resource "aws_scheduler_schedule_group" "monitor" {
  count = local.data_count

  name = "${local.name_prefix}-model-monitor"
  tags = merge(local.tags, { Component = "model-refresh" })
}

resource "aws_scheduler_schedule" "monitor" {
  #checkov:skip=CKV_AWS_297:The schedule input is only the business-unit name and its drift threshold; nothing sensitive to encrypt with a CMK.
  for_each = var.enable_data_platform ? toset(var.business_units) : toset([])

  name                         = "${local.name_prefix}-drift-${each.key}"
  group_name                   = aws_scheduler_schedule_group.monitor[0].name
  description                  = "Daily drift check for ${each.key}"
  schedule_expression          = var.model_monitor_schedule
  schedule_expression_timezone = var.model_refresh_timezone
  state                        = var.enable_model_monitor_schedule ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.monitor_sfn[0].state_machine_arn
    role_arn = aws_iam_role.refresh_trigger[0].arn
    input    = jsonencode({ business_unit = each.key, drift_threshold = local.drift_threshold[each.key] })

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "model_drift" {
  for_each = var.enable_data_platform ? toset(var.business_units) : toset([])

  alarm_name          = "${local.name_prefix}-model-drift-${each.key}"
  alarm_description   = "Model drift for ${each.key} above ${local.drift_threshold[each.key]} - the approved model may no longer fit (runbooks/model-drift.md)"
  namespace           = "MMM/Models"
  metric_name         = "ModelDrift"
  dimensions          = { BusinessUnit = each.key, Check = "overall" }
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = local.drift_threshold[each.key]
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [module.monitoring.alert_topic_arn]
  ok_actions          = [module.monitoring.alert_topic_arn]

  tags = merge(local.tags, { Component = "model-refresh" })
}

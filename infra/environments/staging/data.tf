# ================================================================== Step 13 - Data-team platform and model refresh
# Databricks (Lakeflow job) prepares the training snapshot; SageMaker trains and evaluates; the
# model package is registered as PendingManualApproval and approved by a WBD approver through
# model-governance.yml; the Databricks write-back job copies predictions and lift to Gold.
# Orchestration: EventBridge Scheduler / "mmm.refresh" event -> model-refresh state machine.
# Drift: a daily model-monitor state machine per BU compares new features with the approved
# baseline (alarm; optional automatic refresh). DevOps owns the plumbing; the job code belongs to
# the data team. Everything in this file exists only when enable_data_platform = true.
locals {
  data_platform_kms_purposes = var.enable_data_platform ? [for bu in var.business_units : "s3-${bu}"] : []
  bu_key_arns                = var.enable_data_platform ? { for bu in var.business_units : bu => module.kms.key_arns["s3-${bu}"] } : {}

  data_count = var.enable_data_platform ? 1 : 0

  # Built from the name: the landing bucket policy can't reference the bucket module's own output.
  landing_bucket_arn = "arn:${local.partition}:s3:::wbd-mmm-${local.env_short}-landing-${local.region_code}"

  # Buckets Unity Catalog works on, and their keys.
  data_bucket_names = ["landing", "lakehouse", "training-data"]
  data_key_arns     = concat([module.kms.key_arns["s3"]], values(local.bu_key_arns))

  refresh_name         = "model-refresh"
  refresh_sm_arn       = "arn:${local.partition}:states:${var.aws_region}:${local.account_id}:stateMachine:${local.name_prefix}-${local.refresh_name}"
  monitor_name         = "model-monitor"
  monitor_sm_arn       = "arn:${local.partition}:states:${var.aws_region}:${local.account_id}:stateMachine:${local.name_prefix}-${local.monitor_name}"
  training_job_prefix  = "${local.name_prefix}-train"
  evaluate_job_prefix  = "${local.name_prefix}-eval"
  drift_job_prefix     = "${local.name_prefix}-drift"
  databricks_api       = trimsuffix(var.databricks_host, "/")
  sagemaker_arn_prefix = "arn:${local.partition}:sagemaker:${var.aws_region}:${local.account_id}"
}

# Files under landing/<bu>/ must be encrypted with that business unit's key.
data "aws_iam_policy_document" "landing_bu_keys" {
  dynamic "statement" {
    for_each = local.bu_key_arns
    content {
      sid       = "RequireKeyOf${replace(title(statement.key), "-", "")}"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.landing_bucket_arn}/${statement.key}/*"]

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

# ------------------------------------------------------------------ Databricks: Unity Catalog role, PrivateLink, private DNS
module "databricks_access" {
  source = "../../modules/databricks-access"
  count  = local.data_count

  name_prefix           = local.name_prefix
  databricks_account_id = var.databricks_account_id
  self_assume_enabled   = var.databricks_self_assume_enabled

  bucket_arns  = [for b in local.data_bucket_names : module.buckets[b].bucket_arn]
  kms_key_arns = local.data_key_arns

  # Write-back job reads predictions and lift from the evaluation output
  read_only_prefixes = [{ bucket_arn = module.buckets["models"].bucket_arn, prefix = "evaluation/" }]

  enable_privatelink         = var.enable_databricks_privatelink
  workspace_host             = var.databricks_host
  workspace_service_name     = var.databricks_privatelink_service_name
  vpc_id                     = module.network.vpc_id
  endpoint_subnet_ids        = module.network.private_endpoint_subnet_ids
  endpoint_security_group_id = module.network.security_group_ids["endpoints"]

  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ------------------------------------------------------------------ Databricks connection (OAuth M2M, no token in Terraform)
# Terraform creates the connection with a placeholder secret. DevOps sets the real service
# principal OAuth secret once (docs/05):
#   aws events update-connection --name <name> --authorization-type OAUTH_CLIENT_CREDENTIALS \
#     --auth-parameters 'OAuthParameters={ClientParameters={ClientID=<id>,ClientSecret=<secret>}, ...}'
resource "aws_cloudwatch_event_connection" "databricks" {
  count = local.data_count

  name               = "${local.name_prefix}-databricks"
  description        = "Databricks workspace API (service principal OAuth) for the model-refresh and model-monitor state machines"
  authorization_type = "OAUTH_CLIENT_CREDENTIALS"

  auth_parameters {
    oauth {
      authorization_endpoint = "${local.databricks_api}/oidc/v1/token"
      http_method            = "POST"

      client_parameters {
        client_id     = var.databricks_sp_client_id
        client_secret = "set-out-of-band"
      }

      oauth_http_parameters {
        body {
          key   = "grant_type"
          value = "client_credentials"
        }
        body {
          key   = "scope"
          value = "all-apis"
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [auth_parameters[0].oauth[0].client_parameters[0].client_secret]
  }
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

# ------------------------------------------------------------------ Model-refresh state machine
locals {
  snapshot_uri   = "States.Format('s3://wbd-mmm-${local.env_short}-training-data-${local.region_code}/{}/{}/', $.business_unit, $.refresh_id)"
  evaluation_uri = "States.Format('s3://wbd-mmm-${local.env_short}-models-${local.region_code}/evaluation/{}/{}/', $.business_unit, $.refresh_id)"

  sagemaker_vpc = {
    Subnets          = module.network.private_app_subnet_ids
    SecurityGroupIds = [module.network.security_group_ids["sagemaker"]]
  }

  databricks_retry = [{
    ErrorEquals     = ["States.Http.StatusCode.429", "States.Http.StatusCode.503"]
    IntervalSeconds = 30
    MaxAttempts     = 3
    BackoffRate     = 2
  }]

  refresh_definition = var.enable_data_platform ? {
    Comment        = "MMM model refresh per business unit (${var.environment})"
    StartAt        = "Init"
    TimeoutSeconds = 6 * 3600
    States = {
      # refresh_id names the snapshot, jobs and evaluation (SageMaker job names: max 63 characters)
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
        Next           = "StartDatabricksJob"
      }
      # Lakeflow job: features + training snapshot for one business unit
      StartDatabricksJob = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::http:invoke"
        Parameters = {
          ApiEndpoint    = "${local.databricks_api}/api/2.2/jobs/run-now"
          Method         = "POST"
          Authentication = { ConnectionArn = aws_cloudwatch_event_connection.databricks[0].arn }
          RequestBody = {
            job_id = var.databricks_refresh_job_id
            job_parameters = {
              "business_unit.$" = "$.business_unit"
              "snapshot_uri.$"  = local.snapshot_uri
            }
          }
        }
        ResultSelector = { "run_id.$" = "$.ResponseBody.run_id" }
        ResultPath     = "$.databricks"
        Retry = [{
          ErrorEquals     = ["States.Http.StatusCode.429", "States.Http.StatusCode.503"]
          IntervalSeconds = 30
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Next = "WaitForDatabricks"
      }
      WaitForDatabricks = { Type = "Wait", Seconds = 60, Next = "GetDatabricksRun" }
      GetDatabricksRun = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::http:invoke"
        Parameters = {
          ApiEndpoint     = "${local.databricks_api}/api/2.2/jobs/runs/get"
          Method          = "GET"
          Authentication  = { ConnectionArn = aws_cloudwatch_event_connection.databricks[0].arn }
          QueryParameters = { "run_id.$" = "States.Format('{}', $.databricks.run_id)" }
        }
        ResultSelector = { "state.$" = "$.ResponseBody.state" }
        ResultPath     = "$.databricks.run"
        Retry = [{
          ErrorEquals     = ["States.Http.StatusCode.429", "States.Http.StatusCode.503"]
          IntervalSeconds = 30
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Next = "DatabricksDone"
      }
      DatabricksDone = {
        Type = "Choice"
        Choices = [
          {
            And = [
              { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "TERMINATED" },
              { Variable = "$.databricks.run.state.result_state", IsPresent = true },
              { Variable = "$.databricks.run.state.result_state", StringEquals = "SUCCESS" },
            ]
            Next = "TrainModel"
          },
          {
            Or = [
              { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "TERMINATED" },
              { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "INTERNAL_ERROR" },
              { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "SKIPPED" },
            ]
            Next = "DatabricksFailed"
          },
        ]
        Default = "WaitForDatabricks"
      }
      DatabricksFailed = { Type = "Fail", Error = "DatabricksJobFailed", Cause = "The Databricks refresh job did not succeed; see the run in the Databricks workspace." }
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
      # Same image, argument "evaluate": writes evaluation.json (metrics) next to the hold-out results.
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
              InstanceType   = var.optimizer_instance_type
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
          StoppingCondition = { MaxRuntimeInSeconds = var.optimizer_max_runtime_seconds }
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
            "databricks_run_id.$" = "States.Format('{}', $.databricks.run_id)"
            "refresh_id.$"        = "$.refresh_id"
          }
        }
        ResultSelector = { "model_package_arn.$" = "$.ModelPackageArn" }
        ResultPath     = "$.registered"
        Next           = "StartDatabricksWriteback"
      }
      # Write-back job: predictions/ and lift/ of the evaluation output -> Gold monitoring tables
      # (tagged with model_package_arn; the approval status lives in the registry).
      StartDatabricksWriteback = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::http:invoke"
        Parameters = {
          ApiEndpoint    = "${local.databricks_api}/api/2.2/jobs/run-now"
          Method         = "POST"
          Authentication = { ConnectionArn = aws_cloudwatch_event_connection.databricks[0].arn }
          RequestBody = {
            job_id = var.databricks_writeback_job_id
            job_parameters = {
              "business_unit.$"     = "$.business_unit"
              "refresh_id.$"        = "$.refresh_id"
              "results_uri.$"       = local.evaluation_uri
              "model_package_arn.$" = "$.registered.model_package_arn"
            }
          }
        }
        ResultSelector = { "run_id.$" = "$.ResponseBody.run_id" }
        ResultPath     = "$.writeback"
        Retry          = local.databricks_retry
        Next           = "WaitForWriteback"
      }
      WaitForWriteback = { Type = "Wait", Seconds = 60, Next = "GetWritebackRun" }
      GetWritebackRun = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::http:invoke"
        Parameters = {
          ApiEndpoint     = "${local.databricks_api}/api/2.2/jobs/runs/get"
          Method          = "GET"
          Authentication  = { ConnectionArn = aws_cloudwatch_event_connection.databricks[0].arn }
          QueryParameters = { "run_id.$" = "States.Format('{}', $.writeback.run_id)" }
        }
        ResultSelector = { "state.$" = "$.ResponseBody.state" }
        ResultPath     = "$.writeback.run"
        Retry          = local.databricks_retry
        Next           = "WritebackDone"
      }
      WritebackDone = {
        Type = "Choice"
        Choices = [
          {
            And = [
              { Variable = "$.writeback.run.state.life_cycle_state", StringEquals = "TERMINATED" },
              { Variable = "$.writeback.run.state.result_state", IsPresent = true },
              { Variable = "$.writeback.run.state.result_state", StringEquals = "SUCCESS" },
            ]
            Next = "RefreshComplete"
          },
          {
            Or = [
              { Variable = "$.writeback.run.state.life_cycle_state", StringEquals = "TERMINATED" },
              { Variable = "$.writeback.run.state.life_cycle_state", StringEquals = "INTERNAL_ERROR" },
              { Variable = "$.writeback.run.state.life_cycle_state", StringEquals = "SKIPPED" },
            ]
            Next = "WritebackFailed"
          },
        ]
        Default = "WaitForWriteback"
      }
      WritebackFailed = { Type = "Fail", Error = "WritebackFailed", Cause = "The model package is registered, but the Databricks write-back job did not succeed (runbooks/write-back-failed.md)." }
      RefreshComplete = { Type = "Succeed" }
    }
  } : null
}

data "aws_iam_policy_document" "refresh_sfn" {
  count = local.data_count

  statement {
    sid       = "ReadImagePointer"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sagemaker_image["training"].arn]
  }

  # HTTP Task: only the Databricks workspace, only through the connection.
  statement {
    sid       = "CallDatabricks"
    actions   = ["states:InvokeHTTPEndpoint"]
    resources = [local.refresh_sm_arn]

    condition {
      test     = "StringLike"
      variable = "states:HTTPEndpoint"
      values   = ["${local.databricks_api}/api/2.2/jobs/*"]
    }
  }

  statement {
    sid       = "UseConnection"
    actions   = ["events:RetrieveConnectionCredentials"]
    resources = [aws_cloudwatch_event_connection.databricks[0].arn]
  }

  statement {
    sid       = "ConnectionSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_cloudwatch_event_connection.databricks[0].secret_arn]
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

# On demand: scripts/trigger-model-refresh.sh (or the data team) puts
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
# Per BU, daily: Databricks exports the latest features -> SageMaker Processing (training image,
# argument "drift") compares them with the approved baseline (models/baseline/<bu>/, written by
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

  monitor_states = var.enable_data_platform ? {
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
      Next = "GetTrainingImage"
    }
    GetTrainingImage = {
      Type           = "Task"
      Resource       = "arn:${local.partition}:states:::aws-sdk:ssm:getParameter"
      Parameters     = { Name = aws_ssm_parameter.sagemaker_image["training"].name }
      ResultSelector = { "uri.$" = "$.Parameter.Value" }
      ResultPath     = "$.image"
      Next           = "StartDatabricksExport"
    }
    # Same Lakeflow job as the refresh, purpose = monitor: latest features only, no training snapshot
    StartDatabricksExport = {
      Type     = "Task"
      Resource = "arn:${local.partition}:states:::http:invoke"
      Parameters = {
        ApiEndpoint    = "${local.databricks_api}/api/2.2/jobs/run-now"
        Method         = "POST"
        Authentication = { ConnectionArn = aws_cloudwatch_event_connection.databricks[0].arn }
        RequestBody = {
          job_id = var.databricks_refresh_job_id
          job_parameters = {
            "business_unit.$" = "$.business_unit"
            purpose           = "monitor"
            "snapshot_uri.$"  = local.features_uri
          }
        }
      }
      ResultSelector = { "run_id.$" = "$.ResponseBody.run_id" }
      ResultPath     = "$.databricks"
      Retry          = local.databricks_retry
      Next           = "WaitForExport"
    }
    WaitForExport = { Type = "Wait", Seconds = 60, Next = "GetExportRun" }
    GetExportRun = {
      Type     = "Task"
      Resource = "arn:${local.partition}:states:::http:invoke"
      Parameters = {
        ApiEndpoint     = "${local.databricks_api}/api/2.2/jobs/runs/get"
        Method          = "GET"
        Authentication  = { ConnectionArn = aws_cloudwatch_event_connection.databricks[0].arn }
        QueryParameters = { "run_id.$" = "States.Format('{}', $.databricks.run_id)" }
      }
      ResultSelector = { "state.$" = "$.ResponseBody.state" }
      ResultPath     = "$.databricks.run"
      Retry          = local.databricks_retry
      Next           = "ExportDone"
    }
    ExportDone = {
      Type = "Choice"
      Choices = [
        {
          And = [
            { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "TERMINATED" },
            { Variable = "$.databricks.run.state.result_state", IsPresent = true },
            { Variable = "$.databricks.run.state.result_state", StringEquals = "SUCCESS" },
          ]
          Next = "CheckDrift"
        },
        {
          Or = [
            { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "TERMINATED" },
            { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "INTERNAL_ERROR" },
            { Variable = "$.databricks.run.state.life_cycle_state", StringEquals = "SKIPPED" },
          ]
          Next = "ExportFailed"
        },
      ]
      Default = "WaitForExport"
    }
    ExportFailed = { Type = "Fail", Error = "DatabricksExportFailed", Cause = "The Databricks feature export (purpose=monitor) did not succeed; see the run in the Databricks workspace." }
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
            InstanceType   = var.optimizer_instance_type
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
        StoppingCondition = { MaxRuntimeInSeconds = var.optimizer_max_runtime_seconds }
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
  } : null
}

data "aws_iam_policy_document" "monitor_sfn" {
  count = local.data_count

  statement {
    sid       = "ReadImagePointer"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sagemaker_image["training"].arn]
  }

  statement {
    sid       = "CallDatabricks"
    actions   = ["states:InvokeHTTPEndpoint"]
    resources = [local.monitor_sm_arn]

    condition {
      test     = "StringLike"
      variable = "states:HTTPEndpoint"
      values   = ["${local.databricks_api}/api/2.2/jobs/*"]
    }
  }

  statement {
    sid       = "UseConnection"
    actions   = ["events:RetrieveConnectionCredentials"]
    resources = [aws_cloudwatch_event_connection.databricks[0].arn]
  }

  statement {
    sid       = "ConnectionSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_cloudwatch_event_connection.databricks[0].secret_arn]
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
  definition             = jsonencode({ Comment = "MMM model drift check per business unit (${var.environment})", StartAt = "ApplyDefaults", TimeoutSeconds = 3 * 3600, States = local.monitor_states })
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

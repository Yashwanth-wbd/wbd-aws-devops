# ================================================================== Step 7b - Full optimization (Step Functions + ECS inference & optimization task)
# API -> run queue -> dispatcher StartExecution {run_id, business_unit, input_s3_uri, run_type} (run-queue.tf)
#   -> read the optimizer task definition from SSM -> ECS Fargate task (runTask.sync, private subnets):
#      Model Summarizer + Optimizer + Simulation on the approved response curves and the user input files
#   -> results-publisher Lambda (alias live) writes the summary to RDS; on failure it marks the run failed.
# run_type: optimize (upload inventory + objective) or forecast (upload future titles).
# Progress for the UI = execution status (DescribeExecution; name = run_id) + the run row in RDS.
# deploy.yml adds dry_run = true after a release in dev/staging (scripts/dry-run-optimization.sh):
# the task gets DRY_RUN=true and the publisher dry_run, so neither writes a real run.
locals {
  publisher_name = "results-publisher"

  # SageMaker image URIs (training only): written by deploy.yml (release = new value; rollback = previous value).
  sagemaker_images = var.enable_data_platform ? { training = "mmm/sagemaker-training" } : {}

  ecr_repo_arn_prefix = "arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository"

  optimizer_task_param = "/mmm/${local.env_short}/ecs/optimizer_task_definition"
  cluster_arn          = "arn:${local.partition}:ecs:${var.aws_region}:${local.account_id}:cluster/${module.ecs_cluster.cluster_name}"
  model_package_arns = [
    "arn:${local.partition}:sagemaker:${var.aws_region}:${local.account_id}:model-package-group/${local.name_prefix}-*",
    "arn:${local.partition}:sagemaker:${var.aws_region}:${local.account_id}:model-package/${local.name_prefix}-*/*",
  ]

  seed_optimizer_command = ["python", "-c", "raise SystemExit('seed optimizer task - replaced by deploy.yml')"]
}

# ------------------------------------------------------------------ Release pointers (SSM)
resource "aws_ssm_parameter" "sagemaker_image" {
  #checkov:skip=CKV2_AWS_34:Non-secret image URI; nothing sensitive.
  for_each = local.sagemaker_images

  name        = "/mmm/${local.env_short}/images/sagemaker-${each.key}"
  description = "Image URI of the SageMaker ${each.key} job (set by deploy.yml; Terraform only creates it)"
  type        = "String"
  value       = "${module.ecr.registry}/${each.value}:unset"
  tier        = "Standard"

  tags = merge(local.tags, { Component = "model-refresh", Name = "/mmm/${local.env_short}/images/sagemaker-${each.key}" })

  lifecycle {
    ignore_changes = [value]
  }
}

# Task definition revision every run uses (deploy.yml release = new revision; rollback = previous ARN).
resource "aws_ssm_parameter" "optimizer_task" {
  #checkov:skip=CKV2_AWS_34:Non-secret task definition ARN; nothing sensitive.
  name        = local.optimizer_task_param
  description = "Task definition ARN of the inference & optimization task (set by deploy.yml; Terraform only creates it)"
  type        = "String"
  value       = "${module.task_optimizer.task_definition_family}:unset"
  tier        = "Standard"

  tags = merge(local.tags, { Component = "optimization", Name = local.optimizer_task_param })

  lifecycle {
    ignore_changes = [value]
  }
}

# ------------------------------------------------------------------ SageMaker job log groups (KMS, retention)
# SageMaker writes to these fixed names; created here so they are encrypted and expire.
resource "aws_cloudwatch_log_group" "sagemaker" {
  #checkov:skip=CKV_AWS_338:Retention is set per environment (prod 365 days; dev/staging shorter to save cost).
  for_each = toset(var.enable_data_platform ? ["ProcessingJobs", "TrainingJobs"] : [])

  name              = "/aws/sagemaker/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = module.kms.key_arns["logs"]

  tags = merge(local.tags, { Component = "model-refresh" })
}

# ------------------------------------------------------------------ Inference & optimization task (ECS Fargate)
data "aws_iam_policy_document" "task_optimizer" {
  statement {
    sid       = "ReadApprovedCurves"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["models"], "${local.bucket_arns["models"]}/curves/*"]
  }

  statement {
    sid       = "ReadUserInputFiles"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["uploads"], "${local.bucket_arns["uploads"]}/*"]
  }

  statement {
    sid       = "WriteRunEvidence"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arns["results"], "${local.bucket_arns["results"]}/runs/*"]
  }

  statement {
    sid       = "BucketKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.kms.key_arns["s3"]]
  }

  # Approved model version per business unit (SageMaker Model Registry, data platform)
  statement {
    sid       = "ReadModelRegistry"
    actions   = ["sagemaker:ListModelPackages", "sagemaker:DescribeModelPackage", "sagemaker:DescribeModelPackageGroup"]
    resources = local.model_package_arns
  }

  statement {
    sid       = "RunMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["MMM"]
    }
  }
}

module "task_optimizer" {
  source = "../../modules/ecs-service"

  name_prefix              = local.name_prefix
  service_name             = "optimizer"
  task_role_suffix         = "optimizer"
  cluster_name             = module.ecs_cluster.cluster_name
  execution_role_arn       = module.ecs_cluster.execution_role_arn
  subnet_ids               = module.network.private_app_subnet_ids
  security_group_ids       = [module.network.security_group_ids["optimizer"]]
  permissions_boundary_arn = module.permission_boundary.policy_arn
  task_role_policy_json    = data.aws_iam_policy_document.task_optimizer.json

  image                 = var.seed_image
  command               = local.seed_optimizer_command
  cpu                   = var.optimizer_cpu
  memory                = var.optimizer_memory
  ephemeral_storage_gib = var.optimizer_ephemeral_storage_gib
  environment = {
    APP_ENV                    = var.environment
    AWS_REGION                 = var.aws_region
    MODELS_BUCKET              = module.buckets["models"].bucket_name
    RESULTS_BUCKET             = module.buckets["results"].bucket_name
    UPLOADS_BUCKET             = module.buckets["uploads"].bucket_name
    MODEL_PACKAGE_GROUP_PREFIX = local.name_prefix
  }
  log_retention_days = var.log_retention_days
  logs_kms_key_arn   = module.kms.key_arns["logs"]

  create_service           = false
  enable_execute_command   = false
  exec_audit_log_group_arn = module.ecs_cluster.exec_audit_log_group_arn
  exec_kms_key_arn         = module.ecs_cluster.exec_kms_key_arn
}

# ------------------------------------------------------------------ Results publisher (Lambda)
data "aws_iam_policy_document" "publisher" {
  statement {
    sid       = "DbConnectAsAppUser"
    actions   = ["rds-db:connect"]
    resources = ["${local.proxy_dbuser_arn}/mmm_app"]
  }

  statement {
    sid       = "ReadRunOutput"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [module.buckets["results"].bucket_arn, "${module.buckets["results"].bucket_arn}/runs/*"]
  }

  # model_results events (model refresh): predictions, lift and evaluation of a refresh
  dynamic "statement" {
    for_each = var.enable_data_platform ? [1] : []
    content {
      sid       = "ReadEvaluationOutput"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = [module.buckets["models"].bucket_arn, "${module.buckets["models"].bucket_arn}/evaluation/*"]
    }
  }

  # reference_data events (model refresh): Gold reference tables exported by Glue export-rds
  dynamic "statement" {
    for_each = var.enable_data_platform ? [1] : []
    content {
      sid       = "ReadReferenceDataExport"
      actions   = ["s3:GetObject"]
      resources = ["${module.buckets["lakehouse"].bucket_arn}/${local.rds_export_prefix}*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_data_platform ? [1] : []
    content {
      sid       = "ListReferenceDataExport"
      actions   = ["s3:ListBucket"]
      resources = [module.buckets["lakehouse"].bucket_arn]

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["${local.rds_export_prefix}*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_data_platform ? [1] : []
    content {
      sid       = "ReferenceDataMetrics"
      actions   = ["cloudwatch:PutMetricData"]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "cloudwatch:namespace"
        values   = ["MMM/Data"]
      }
    }
  }

  statement {
    sid       = "BucketKey"
    actions   = ["kms:Decrypt"]
    resources = concat([module.kms.key_arns["s3"]], values(local.bu_key_arns))
  }
}

module "publisher" {
  source = "../../modules/lambda-function"

  name_prefix = local.name_prefix
  name        = local.publisher_name
  description = "Results/data publisher: writes optimization runs, Gold reference data and model results (predictions, lift, evaluation) from S3 to RDS (code shipped by deploy.yml)"
  timeout     = var.publisher_timeout_seconds
  memory_size = var.publisher_memory_mb
  environment = merge({
    APP_ENV        = var.environment
    DB_HOST        = module.rds.proxy_endpoint
    DB_PORT        = "5432"
    DB_NAME        = module.rds.db_name
    DB_USER        = "mmm_app"
    RESULTS_BUCKET = module.buckets["results"].bucket_name
    MODELS_BUCKET  = module.buckets["models"].bucket_name
  }, var.enable_data_platform ? { LAKEHOUSE_BUCKET = module.buckets["lakehouse"].bucket_name } : {})
  policy_json = data.aws_iam_policy_document.publisher.json

  subnet_ids         = module.network.private_app_subnet_ids
  security_group_ids = [module.network.security_group_ids["lambda"], module.network.security_group_ids["data_clients"]]

  kms_key_arn              = module.kms.key_arns["secrets"]
  logs_kms_key_arn         = module.kms.key_arns["logs"]
  log_retention_days       = var.log_retention_days
  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
  component                = "optimization"
}

# ------------------------------------------------------------------ State machine
locals {
  publish_step = {
    Type     = "Task"
    Resource = "arn:${local.partition}:states:::lambda:invoke"
    Retry = [{
      ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
      IntervalSeconds = 5
      MaxAttempts     = 3
      BackoffRate     = 2
    }]
  }

  run_output_uri = "States.Format('s3://${module.buckets["results"].bucket_name}/runs/{}/output/', $.run_id)"

  optimization_definition = {
    Comment = "MMM full optimization run (${var.environment})"
    StartAt = "ApplyDefaults"
    States = {
      ApplyDefaults = {
        Type       = "Pass"
        Parameters = { "args.$" = "States.JsonMerge(States.StringToJson('{\"dry_run\":false,\"run_type\":\"optimize\"}'), $, false)" }
        OutputPath = "$.args"
        Next       = "GetOptimizerTask"
      }
      GetOptimizerTask = {
        Type           = "Task"
        Resource       = "arn:${local.partition}:states:::aws-sdk:ssm:getParameter"
        Parameters     = { Name = aws_ssm_parameter.optimizer_task.name }
        ResultSelector = { "arn.$" = "$.Parameter.Value" }
        ResultPath     = "$.task"
        Next           = "RunOptimizer"
      }
      # Model Summarizer -> Optimizer -> Simulation in one task; a non-zero exit fails the state.
      RunOptimizer = {
        Type           = "Task"
        Resource       = "arn:${local.partition}:states:::ecs:runTask.sync"
        TimeoutSeconds = var.optimizer_max_runtime_seconds
        Parameters = {
          Cluster            = local.cluster_arn
          LaunchType         = "FARGATE"
          "TaskDefinition.$" = "$.task.arn"
          PropagateTags      = "TASK_DEFINITION"
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = module.network.private_app_subnet_ids
              SecurityGroups = [module.network.security_group_ids["optimizer"]]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [{
              Name = "app"
              Environment = [
                { Name = "RUN_ID", "Value.$" = "$.run_id" },
                { Name = "BUSINESS_UNIT", "Value.$" = "$.business_unit" },
                { Name = "RUN_TYPE", "Value.$" = "$.run_type" },
                { Name = "INPUT_S3_URI", "Value.$" = "$.input_s3_uri" },
                { Name = "OUTPUT_S3_URI", "Value.$" = local.run_output_uri },
                { Name = "CURVES_S3_URI", "Value.$" = "States.Format('s3://${module.buckets["models"].bucket_name}/curves/{}/', $.business_unit)" },
                { Name = "DRY_RUN", "Value.$" = "States.Format('{}', $.dry_run)" },
              ]
            }]
          }
          Tags = [{ Key = "run_id", "Value.$" = "$.run_id" }, { Key = "business_unit", "Value.$" = "$.business_unit" }]
        }
        ResultSelector = { "task_arn.$" = "$.TaskArn" }
        ResultPath     = "$.job"
        # No capacity / quota at the moment: wait and try again (the run stays "running" for the planner).
        Retry = [{
          ErrorEquals     = ["ECS.AmazonECSException", "ECS.ServerException", "ECS.LimitExceededException", "ThrottlingException"]
          IntervalSeconds = 30
          MaxAttempts     = 5
          BackoffRate     = 2
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "PublishFailure" }]
        Next  = "PublishResult"
      }
      PublishResult = merge(local.publish_step, {
        Parameters = {
          FunctionName = module.publisher.alias_arn
          Payload = {
            event             = "optimization_run"
            "run_id.$"        = "$.run_id"
            "business_unit.$" = "$.business_unit"
            "run_type.$"      = "$.run_type"
            status            = "SUCCEEDED"
            "output_s3_uri.$" = local.run_output_uri
            "dry_run.$"       = "$.dry_run"
          }
        }
        ResultPath = null
        End        = true
      })
      PublishFailure = merge(local.publish_step, {
        Parameters = {
          FunctionName = module.publisher.alias_arn
          Payload = {
            event             = "optimization_run"
            "run_id.$"        = "$.run_id"
            "business_unit.$" = "$.business_unit"
            "run_type.$"      = "$.run_type"
            status            = "FAILED"
            "error.$"         = "$.error"
            "dry_run.$"       = "$.dry_run"
          }
        }
        ResultPath = null
        Next       = "RunFailed"
      })
      RunFailed = { Type = "Fail", Error = "OptimizationFailed", Cause = "The optimizer task failed; see the execution history and /ecs/${local.name_prefix}/optimizer." }
    }
  }
}

data "aws_iam_policy_document" "optimization_sfn" {
  statement {
    sid       = "ReadTaskPointer"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.optimizer_task.arn]
  }

  statement {
    sid       = "RunOptimizerTask"
    actions   = ["ecs:RunTask"]
    resources = ["arn:${local.partition}:ecs:${var.aws_region}:${local.account_id}:task-definition/${module.task_optimizer.task_definition_family}:*"]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [local.cluster_arn]
    }
  }

  statement {
    sid       = "WatchOptimizerTask"
    actions   = ["ecs:StopTask", "ecs:DescribeTasks"]
    resources = ["arn:${local.partition}:ecs:${var.aws_region}:${local.account_id}:task/${module.ecs_cluster.cluster_name}/*"]
  }

  statement {
    sid       = "TagOnRun"
    actions   = ["ecs:TagResource"]
    resources = ["arn:${local.partition}:ecs:${var.aws_region}:${local.account_id}:task/${module.ecs_cluster.cluster_name}/*"]

    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RunTask"]
    }
  }

  # .sync integration: Step Functions watches the task through this managed EventBridge rule.
  statement {
    sid       = "SyncRule"
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"]
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = [module.task_optimizer.task_role_arn, module.ecs_cluster.execution_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "InvokePublisher"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.publisher.alias_arn]
  }
}

module "optimization_sfn" {
  source = "../../modules/step-functions"

  name_prefix            = local.name_prefix
  name                   = "optimization"
  definition             = jsonencode(local.optimization_definition)
  role_policy_json       = data.aws_iam_policy_document.optimization_sfn.json
  include_execution_data = !local.is_prod
  component              = "optimization"

  logs_kms_key_arn         = module.kms.key_arns["logs"]
  log_retention_days       = var.log_retention_days
  alarm_topic_arn          = module.monitoring.alert_topic_arn
  permissions_boundary_arn = module.permission_boundary.policy_arn
}

# ================================================================== Step 7b - Full optimization (Step Functions + SageMaker)
# API -> StartExecution {run_id, business_unit, input_s3_uri}
#   -> read the optimizer image from SSM -> SageMaker Processing job (.sync, private subnets)
#   -> results-publisher Lambda (alias live) writes the summary to Aurora; on failure it marks the run failed.
# Progress for the UI = execution status (DescribeExecution) + the run row in Aurora; no queue, no cache.
# deploy.yml adds dry_run = true after a release in dev/staging (scripts/dry-run-optimization.sh):
# the job gets DRY_RUN=true and the publisher dry_run, so neither writes a real run.
locals {
  publisher_name = "results-publisher"

  # Image URIs: written by deploy.yml (release = new value; rollback = previous value).
  sagemaker_images = merge(
    { optimizer = "mmm/sagemaker-optimizer" },
    var.enable_data_platform ? { training = "mmm/sagemaker-training" } : {},
  )

  ecr_repo_arn_prefix = "arn:${local.partition}:ecr:${var.aws_region}:${local.account_id}:repository"

  optimization_job_prefix = "${local.name_prefix}-opt"
}

# ------------------------------------------------------------------ Image pointers (SSM)
resource "aws_ssm_parameter" "sagemaker_image" {
  #checkov:skip=CKV2_AWS_34:Non-secret image URI; nothing sensitive.
  for_each = local.sagemaker_images

  name        = "/mmm/${local.env_short}/images/sagemaker-${each.key}"
  description = "Image URI of the SageMaker ${each.key} job (set by deploy.yml; Terraform only creates it)"
  type        = "String"
  value       = "${module.ecr.registry}/${each.value}:unset"
  tier        = "Standard"

  tags = merge(local.tags, { Component = "optimization", Name = "/mmm/${local.env_short}/images/sagemaker-${each.key}" })

  lifecycle {
    ignore_changes = [value]
  }
}

# ------------------------------------------------------------------ SageMaker job log groups (KMS, retention)
# SageMaker writes to these fixed names; created here so they are encrypted and expire.
resource "aws_cloudwatch_log_group" "sagemaker" {
  #checkov:skip=CKV_AWS_338:Retention is set per environment (prod 365 days; dev/staging shorter to save cost).
  for_each = toset(concat(["ProcessingJobs"], var.enable_data_platform ? ["TrainingJobs"] : []))

  name              = "/aws/sagemaker/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = module.kms.key_arns["logs"]

  tags = merge(local.tags, { Component = "optimization" })
}

# ------------------------------------------------------------------ Optimizer execution role
module "sagemaker_optimization" {
  source = "../../modules/sagemaker"

  name_prefix         = local.name_prefix
  name                = "optimization"
  read_bucket_arns    = [module.buckets["models"].bucket_arn, module.buckets["results"].bucket_arn]
  write_bucket_arns   = [module.buckets["results"].bucket_arn]
  data_kms_key_arns   = [module.kms.key_arns["s3"]]
  volume_kms_key_arn  = module.kms.key_arns["sagemaker"]
  ecr_repository_arns = ["${local.ecr_repo_arn_prefix}/mmm/sagemaker-optimizer"]

  permissions_boundary_arn = module.permission_boundary.policy_arn
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

  statement {
    sid       = "BucketKey"
    actions   = ["kms:Decrypt"]
    resources = [module.kms.key_arns["s3"]]
  }
}

module "publisher" {
  source = "../../modules/lambda-function"

  name_prefix = local.name_prefix
  name        = local.publisher_name
  description = "Writes the summary of a finished optimization run from S3 to Aurora (code shipped by deploy.yml)"
  timeout     = 120
  environment = {
    APP_ENV        = var.environment
    DB_HOST        = module.aurora.proxy_endpoint
    DB_PORT        = "5432"
    DB_NAME        = module.aurora.db_name
    DB_USER        = "mmm_app"
    RESULTS_BUCKET = module.buckets["results"].bucket_name
  }
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

  optimization_definition = {
    Comment = "MMM full optimization run (${var.environment})"
    StartAt = "ApplyDefaults"
    States = {
      ApplyDefaults = {
        Type       = "Pass"
        Parameters = { "args.$" = "States.JsonMerge(States.StringToJson('{\"dry_run\":false}'), $, false)" }
        OutputPath = "$.args"
        Next       = "GetOptimizerImage"
      }
      GetOptimizerImage = {
        Type           = "Task"
        Resource       = "arn:${local.partition}:states:::aws-sdk:ssm:getParameter"
        Parameters     = { Name = aws_ssm_parameter.sagemaker_image["optimizer"].name }
        ResultSelector = { "uri.$" = "$.Parameter.Value" }
        ResultPath     = "$.image"
        Next           = "RunOptimizer"
      }
      RunOptimizer = {
        Type     = "Task"
        Resource = "arn:${local.partition}:states:::sagemaker:createProcessingJob.sync"
        Parameters = {
          "ProcessingJobName.$" = "States.Format('${local.optimization_job_prefix}-{}', $.run_id)"
          RoleArn               = module.sagemaker_optimization.role_arn
          AppSpecification      = { "ImageUri.$" = "$.image.uri" }
          Environment = {
            APP_ENV           = var.environment
            "RUN_ID.$"        = "$.run_id"
            "BUSINESS_UNIT.$" = "$.business_unit"
            "DRY_RUN.$"       = "States.Format('{}', $.dry_run)"
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
            {
              InputName = "input"
              S3Input   = { "S3Uri.$" = "$.input_s3_uri", LocalPath = "/opt/ml/processing/input", S3DataType = "S3Prefix", S3InputMode = "File" }
            },
            {
              InputName = "curves"
              S3Input   = { "S3Uri.$" = "States.Format('s3://${module.buckets["models"].bucket_name}/curves/{}/', $.business_unit)", LocalPath = "/opt/ml/processing/curves", S3DataType = "S3Prefix", S3InputMode = "File" }
            },
          ]
          ProcessingOutputConfig = {
            KmsKeyId = module.kms.key_arns["s3"]
            Outputs = [{
              OutputName = "result"
              S3Output   = { "S3Uri.$" = "States.Format('s3://${module.buckets["results"].bucket_name}/runs/{}/output/', $.run_id)", LocalPath = "/opt/ml/processing/output", S3UploadMode = "EndOfJob" }
            }]
          }
          StoppingCondition = { MaxRuntimeInSeconds = var.optimizer_max_runtime_seconds }
          NetworkConfig = {
            EnableInterContainerTrafficEncryption = true
            VpcConfig = {
              Subnets          = module.network.private_app_subnet_ids
              SecurityGroupIds = [module.network.security_group_ids["sagemaker"]]
            }
          }
          Tags = [{ Key = "run_id", "Value.$" = "$.run_id" }]
        }
        ResultSelector = { "name.$" = "$.ProcessingJobName", "status.$" = "$.ProcessingJobStatus" }
        ResultPath     = "$.job"
        Retry = [{
          ErrorEquals     = ["SageMaker.ResourceLimitExceededException", "ThrottlingException"]
          IntervalSeconds = 60
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
            "run_id.$"        = "$.run_id"
            "business_unit.$" = "$.business_unit"
            status            = "SUCCEEDED"
            "output_s3_uri.$" = "States.Format('s3://${module.buckets["results"].bucket_name}/runs/{}/output/', $.run_id)"
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
            "run_id.$"        = "$.run_id"
            "business_unit.$" = "$.business_unit"
            status            = "FAILED"
            "error.$"         = "$.error"
            "dry_run.$"       = "$.dry_run"
          }
        }
        ResultPath = null
        Next       = "RunFailed"
      })
      RunFailed = { Type = "Fail", Error = "OptimizationFailed", Cause = "The SageMaker optimization job failed; see the execution history and /aws/sagemaker/ProcessingJobs." }
    }
  }
}

data "aws_iam_policy_document" "optimization_sfn" {
  statement {
    sid       = "ReadImagePointer"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.sagemaker_image["optimizer"].arn]
  }

  statement {
    sid       = "RunProcessingJobs"
    actions   = ["sagemaker:CreateProcessingJob", "sagemaker:DescribeProcessingJob", "sagemaker:StopProcessingJob", "sagemaker:AddTags", "sagemaker:ListTags"]
    resources = ["arn:${local.partition}:sagemaker:${var.aws_region}:${local.account_id}:processing-job/${local.optimization_job_prefix}-*"]
  }

  # .sync integration: Step Functions watches the job through this managed EventBridge rule.
  statement {
    sid       = "SyncRule"
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["arn:${local.partition}:events:${var.aws_region}:${local.account_id}:rule/StepFunctionsGetEventsForSageMakerProcessingJobsRule"]
  }

  statement {
    sid       = "PassJobRole"
    actions   = ["iam:PassRole"]
    resources = [module.sagemaker_optimization.role_arn]

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

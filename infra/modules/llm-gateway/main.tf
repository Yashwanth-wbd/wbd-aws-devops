data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name      = "${var.name_prefix}-llm-gateway"
  tags      = merge(var.tags, { Component = "genai" })
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.name

  providers = { for p, cfg in var.llm_providers : p => merge(cfg, { secret_arn = var.provider_secret_arns[p] }) }
}

# ------------------------------------------------------------------ Proxy Lambda (DevOps-owned code in lambda/)
data "archive_file" "proxy" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.root}/.terraform/tmp/${local.name}.zip"
}

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name                 = "${local.name}-lambda"
  description          = "LLM gateway proxy of ${var.name_prefix}"
  assume_role_policy   = data.aws_iam_policy_document.lambda_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

data "aws_iam_policy_document" "proxy" {
  #checkov:skip=CKV_AWS_356:ENI management and X-Ray calls do not support resource-level permissions.
  #checkov:skip=CKV_AWS_111:ENI management (Lambda in a VPC) does not support resource-level permissions.
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.proxy.arn}:*"]
  }

  statement {
    sid = "VpcNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  statement {
    sid       = "ProviderKeys"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(var.provider_secret_arns)
  }

  statement {
    sid       = "Keys"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn, var.guardrail_kms_key_arn]
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [var.guardrail_arn]
  }
}

resource "aws_iam_role_policy" "proxy" {
  name   = "llm-gateway"
  role   = aws_iam_role.proxy.id
  policy = data.aws_iam_policy_document.proxy.json
}

resource "aws_lambda_function" "proxy" {
  #checkov:skip=CKV_AWS_272:Code signing needs AWS Signer profiles from WBD; the zip is built from Git by Terraform.
  #checkov:skip=CKV_AWS_116:Invoked synchronously by API Gateway; the caller gets the error and retries.
  function_name    = local.name
  description      = "Forwards /<provider>/... to the approved LLM providers; guardrail on every prompt and answer"
  role             = aws_iam_role.proxy.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.proxy.output_path
  source_code_hash = data.archive_file.proxy.output_base64sha256
  timeout          = 30
  memory_size      = 512
  kms_key_arn      = var.secrets_kms_key_arn

  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      PROVIDERS         = jsonencode(local.providers)
      GUARDRAIL_ID      = var.guardrail_id
      GUARDRAIL_VERSION = var.guardrail_version
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.proxy.name
  }

  tags = merge(local.tags, { Name = local.name })

  depends_on = [aws_iam_role_policy.proxy]
}

# ------------------------------------------------------------------ Private REST API (IAM auth, VPC endpoint only)
data "aws_iam_policy_document" "api" {
  statement {
    sid       = "InvokeFromApiTasks"
    actions   = ["execute-api:Invoke"]
    resources = ["execute-api:/*"]

    principals {
      type        = "AWS"
      identifiers = var.invoker_role_arns
    }
  }

  statement {
    sid       = "OnlyThroughTheVpcEndpoint"
    effect    = "Deny"
    actions   = ["execute-api:Invoke"]
    resources = ["execute-api:/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [var.vpc_endpoint_id]
    }
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name        = local.name
  description = "MMM GenAI gateway (private): /openai, /anthropic, /google"
  policy      = data.aws_iam_policy_document.api.json

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [var.vpc_endpoint_id]
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  #checkov:skip=CKV2_AWS_53:Pass-through proxy; the provider request body is validated by the proxy Lambda and the guardrail.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.proxy.invoke_arn
  timeout_milliseconds    = 29000
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowLlmGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_rest_api.this.policy,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_integration.proxy.uri,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = local.tags
}

resource "aws_api_gateway_stage" "v1" {
  #checkov:skip=CKV_AWS_120:Responses are per request (LLM answers); caching would serve one planner's answer to another.
  #checkov:skip=CKV2_AWS_29:Private API reachable only through the VPC endpoint; the public WAF is on the ALB.
  #checkov:skip=CKV2_AWS_51:Private API with IAM auth; mutual TLS is not used inside the VPC.
  rest_api_id          = aws_api_gateway_rest_api.this.id
  deployment_id        = aws_api_gateway_deployment.this.id
  stage_name           = "v1"
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId         = "$context.requestId", caller = "$context.identity.caller", path = "$context.path",
      method            = "$context.httpMethod", status = "$context.status", latencyMs = "$context.responseLatency",
      integrationStatus = "$context.integration.status", vpce = "$context.identity.vpceId",
    })
  }

  tags = local.tags

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_api_gateway_method_settings" "all" {
  #checkov:skip=CKV_AWS_225:Responses are per request (LLM answers); caching would serve one planner's answer to another.
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.v1.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "ERROR"
    data_trace_enabled     = false
    throttling_rate_limit  = var.throttle_rate_per_second
    throttling_burst_limit = var.throttle_burst
  }
}

# ------------------------------------------------------------------ Account-level CloudWatch role (one per account and region)
data "aws_iam_policy_document" "apigw_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_logs" {
  count = var.manage_account_logging_role ? 1 : 0

  name                 = "${var.name_prefix}-apigw-cloudwatch"
  assume_role_policy   = data.aws_iam_policy_document.apigw_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "apigw_logs" {
  count = var.manage_account_logging_role ? 1 : 0

  role       = aws_iam_role.apigw_logs[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  count = var.manage_account_logging_role ? 1 : 0

  cloudwatch_role_arn = aws_iam_role.apigw_logs[0].arn
}

# ------------------------------------------------------------------ Alarms
resource "aws_cloudwatch_metric_alarm" "errors_5xx" {
  alarm_name          = "${local.name}-5xx"
  alarm_description   = "LLM gateway 5xx (provider down, timeout or proxy error) - see ${aws_cloudwatch_log_group.proxy.name}"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions          = { ApiName = aws_api_gateway_rest_api.this.name, Stage = aws_api_gateway_stage.v1.stage_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.error_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

# 4xx = throttled (429), blocked by the guardrail or a bad request from the API.
resource "aws_cloudwatch_metric_alarm" "errors_4xx" {
  alarm_name          = "${local.name}-4xx"
  alarm_description   = "LLM gateway 4xx > ${var.client_error_alarm_threshold} in 5 minutes (throttling 429, guardrail blocks or bad requests) - see ${aws_cloudwatch_log_group.proxy.name}"
  namespace           = "AWS/ApiGateway"
  metric_name         = "4XXError"
  dimensions          = { ApiName = aws_api_gateway_rest_api.this.name, Stage = aws_api_gateway_stage.v1.stage_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.client_error_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "latency" {
  alarm_name          = "${local.name}-latency-p95"
  alarm_description   = "LLM gateway p95 latency > ${var.latency_p95_ms / 1000}s for 3 of 5 periods of 5 minutes (provider slow)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiName = aws_api_gateway_rest_api.this.name, Stage = aws_api_gateway_stage.v1.stage_name }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.latency_p95_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

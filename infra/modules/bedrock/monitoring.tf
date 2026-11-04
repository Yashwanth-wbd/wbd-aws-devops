# ------------------------------------------------------------------ Alarms (AWS/Bedrock per approved model)
locals {
  model_alarms = merge([
    for id in var.approved_model_ids : {
      "${id}|server-errors" = { model = id, metric = "InvocationServerErrors", stat = "Sum", extended = null, threshold = var.server_error_threshold, periods = 3, what = "Bedrock server errors" }
      "${id}|client-errors" = { model = id, metric = "InvocationClientErrors", stat = "Sum", extended = null, threshold = var.client_error_threshold, periods = 3, what = "Bedrock client errors (bad requests, access denied)" }
      "${id}|throttles"     = { model = id, metric = "InvocationThrottles", stat = "Sum", extended = null, threshold = var.throttle_threshold, periods = 3, what = "Bedrock throttling (quota too low for the load)" }
      "${id}|latency-p95"   = { model = id, metric = "InvocationLatency", stat = null, extended = "p95", threshold = var.latency_p95_ms, periods = 3, what = "Bedrock p95 latency in ms" }
    }
  ]...)

  # Alarm names cannot contain ":"; model IDs do (anthropic.claude-...-v1:0).
  model_slug = { for id in var.approved_model_ids : id => replace(replace(id, ":", "-"), ".", "-") }

  total_daily_token_quota = sum(concat([0], values(var.token_quotas)))
}

resource "aws_cloudwatch_metric_alarm" "model" {
  for_each = local.model_alarms

  alarm_name          = "${var.name_prefix}-genai-${local.model_slug[each.value.model]}-${split("|", each.key)[1]}"
  alarm_description   = "${each.value.what} for ${each.value.model} above ${each.value.threshold}. Runbook: docs/runbooks/genai.md"
  namespace           = "AWS/Bedrock"
  metric_name         = each.value.metric
  dimensions          = { ModelId = each.value.model }
  statistic           = each.value.stat
  extended_statistic  = each.value.extended
  period              = 300
  evaluation_periods  = each.value.periods
  datapoints_to_alarm = each.value.periods
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = compact([var.alert_topic_arn])
  ok_actions          = compact([var.alert_topic_arn])

  tags = local.tags
}

# Rolling 24 h tokens of all approved models against the sum of the per-BU quotas.
resource "aws_cloudwatch_metric_alarm" "daily_tokens_total" {
  count = local.total_daily_token_quota > 0 ? 1 : 0

  alarm_name          = "${var.name_prefix}-genai-daily-tokens"
  alarm_description   = "Bedrock input+output tokens in the last 24 h above the total daily quota (${local.total_daily_token_quota}). Runbook: docs/runbooks/genai.md"
  evaluation_periods  = 1
  threshold           = local.total_daily_token_quota
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = compact([var.alert_topic_arn])

  metric_query {
    id          = "total"
    expression  = join(" + ", concat([for i, _ in var.approved_model_ids : "in${i}"], [for i, _ in var.approved_model_ids : "out${i}"]))
    label       = "Tokens (24 h)"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = { for i, id in var.approved_model_ids : "in${i}" => { id = id, metric = "InputTokenCount" } }

    content {
      id = metric_query.key
      metric {
        namespace   = "AWS/Bedrock"
        metric_name = metric_query.value.metric
        dimensions  = { ModelId = metric_query.value.id }
        period      = 86400
        stat        = "Sum"
      }
    }
  }

  dynamic "metric_query" {
    for_each = { for i, id in var.approved_model_ids : "out${i}" => { id = id, metric = "OutputTokenCount" } }

    content {
      id = metric_query.key
      metric {
        namespace   = "AWS/Bedrock"
        metric_name = metric_query.value.metric
        dimensions  = { ModelId = metric_query.value.id }
        period      = 86400
        stat        = "Sum"
      }
    }
  }

  tags = local.tags
}

# Per-BU tokens are published by the gateway (EMF, namespace MMM/GenAI) after every call.
resource "aws_cloudwatch_metric_alarm" "daily_tokens_bu" {
  for_each = var.token_quotas

  alarm_name          = "${var.name_prefix}-genai-daily-tokens-${each.key}"
  alarm_description   = "GenAI tokens of business unit ${each.key} in the last 24 h above its quota (${each.value}). Runbook: docs/runbooks/genai.md"
  namespace           = "MMM/GenAI"
  metric_name         = "Tokens"
  dimensions          = { Environment = var.environment, BusinessUnit = each.key }
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = each.value
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = compact([var.alert_topic_arn])

  tags = local.tags
}

# ------------------------------------------------------------------ Dashboard
locals {
  model_metric = { for m in ["Invocations", "InputTokenCount", "OutputTokenCount", "InvocationServerErrors", "InvocationClientErrors", "InvocationThrottles"] : m => [
    for id in var.approved_model_ids : ["AWS/Bedrock", m, "ModelId", id]
  ] }

  dashboard_widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = { title = "Invocations per model", region = local.region, stat = "Sum", period = 300, metrics = local.model_metric["Invocations"] } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = { title = "Latency p95 (ms)", region = local.region, stat = "p95", period = 300, metrics = [for id in var.approved_model_ids : ["AWS/Bedrock", "InvocationLatency", "ModelId", id]] } },
    { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = { title = "Tokens (input / output)", region = local.region, stat = "Sum", period = 3600, metrics = concat(local.model_metric["InputTokenCount"], local.model_metric["OutputTokenCount"]) } },
    { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = { title = "Errors and throttles", region = local.region, stat = "Sum", period = 300, metrics = concat(local.model_metric["InvocationServerErrors"], local.model_metric["InvocationClientErrors"], local.model_metric["InvocationThrottles"]) } },
    { type = "metric", x = 0, y = 12, width = 12, height = 6, properties = { title = "Tokens per business unit (gateway)", region = local.region, stat = "Sum", period = 3600, metrics = [for bu in keys(var.token_quotas) : ["MMM/GenAI", "Tokens", "Environment", var.environment, "BusinessUnit", bu]] } },
    { type = "metric", x = 12, y = 12, width = 12, height = 6, properties = { title = "Guardrail interventions", region = local.region, period = 300, metrics = [[{ expression = "SEARCH('{AWS/Bedrock/Guardrails} MetricName=\"InvocationsIntervened\"', 'Sum', 300)", id = "g1", label = "" }]] } },
    { type = "metric", x = 0, y = 18, width = 12, height = 6, properties = { title = "Gateway CPU / memory (%)", region = local.region, stat = "Average", period = 300, metrics = [["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.gateway_service_name], ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.gateway_service_name]] } },
    { type = "log", x = 12, y = 18, width = 12, height = 6, properties = { title = "Gateway errors", region = local.region, query = "SOURCE '${var.gateway_log_group_name}' | fields @timestamp, level, event, business_unit, error | filter level = \"ERROR\" | sort @timestamp desc | limit 50" } },
  ]
}

resource "aws_cloudwatch_dashboard" "genai" {
  dashboard_name = "${var.name_prefix}-genai"
  dashboard_body = jsonencode({ widgets = [for w in local.dashboard_widgets : w if length(try(w.properties.metrics, [1])) > 0] })
}

# ------------------------------------------------------------------ Cost
# Third-party models (e.g. Anthropic) are billed under their own Marketplace service names, so
# budget_service_names must list every name Cost Explorer shows for the approved models.
resource "aws_budgets_budget" "genai" {
  name         = "${var.name_prefix}-genai-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = var.budget_service_names
  }

  dynamic "notification" {
    for_each = [50, 80, 100]

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }

  tags = local.tags
}

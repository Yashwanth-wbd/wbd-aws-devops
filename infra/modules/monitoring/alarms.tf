locals {
  actions = [aws_sns_topic.alerts.arn]

  # Decided on the map keys (known at plan time); the ARNs may only be known after apply.
  has_optimization  = contains(keys(var.state_machine_arns), "optimization")
  has_model_refresh = contains(keys(var.state_machine_arns), "model-refresh")
  optimization_sm   = lookup(var.state_machine_arns, "optimization", "")
  model_refresh_sm  = lookup(var.state_machine_arns, "model-refresh", "")

  # Simple single-metric alarms; anything with metric math is written out below.
  simple_alarms = merge(
    { for svc, tg in var.target_group_arn_suffixes : "${svc}-no-healthy-targets" => {
      description = "${svc} target group has no healthy task - the ${svc == "ui" ? "web app" : "API"} is down"
      namespace   = "AWS/ApplicationELB"
      metric      = "HealthyHostCount"
      dimensions  = { LoadBalancer = var.alb_arn_suffix, TargetGroup = tg }
      statistic   = "Minimum"
      period      = 60
      evaluations = 2
      threshold   = 1
      operator    = "LessThanThreshold"
      missing     = "breaching"
    } },
    {
      rds-cpu = {
        description = "RDS CPU > ${var.rds_cpu_percent}% for 15 minutes - check slow queries (Performance Insights) or move to a larger rds_instance_class"
        namespace   = "AWS/RDS"
        metric      = "CPUUtilization"
        dimensions  = { DBInstanceIdentifier = var.rds_instance_id }
        statistic   = "Average"
        period      = 300
        evaluations = 3
        threshold   = var.rds_cpu_percent
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
      }
      # Storage autoscaling grows the volume up to rds_max_allocated_storage; this fires when it is close.
      rds-free-storage = {
        description = "RDS free storage < ${var.rds_free_storage_gib} GiB for 15 minutes - autoscaling may be at rds_max_allocated_storage; raise it"
        namespace   = "AWS/RDS"
        metric      = "FreeStorageSpace"
        dimensions  = { DBInstanceIdentifier = var.rds_instance_id }
        statistic   = "Minimum"
        period      = 300
        evaluations = 3
        threshold   = var.rds_free_storage_gib * 1073741824
        operator    = "LessThanThreshold"
        missing     = "notBreaching"
      }
      rds-read-latency = {
        description = "RDS read latency > ${var.rds_latency_ms} ms for 15 minutes - check IOPS / slow queries"
        namespace   = "AWS/RDS"
        metric      = "ReadLatency"
        dimensions  = { DBInstanceIdentifier = var.rds_instance_id }
        statistic   = "Average"
        period      = 300
        evaluations = 3
        threshold   = var.rds_latency_ms / 1000
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
      }
      rds-write-latency = {
        description = "RDS write latency > ${var.rds_latency_ms} ms for 15 minutes - check IOPS / large writes"
        namespace   = "AWS/RDS"
        metric      = "WriteLatency"
        dimensions  = { DBInstanceIdentifier = var.rds_instance_id }
        statistic   = "Average"
        period      = 300
        evaluations = 3
        threshold   = var.rds_latency_ms / 1000
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
      }
    },
    var.rds_max_connections == null ? {} : {
      rds-connections = {
        description = "RDS connections > ${var.rds_connections_percent}% of max_connections (${coalesce(var.rds_max_connections, 0)}) for 10 minutes - check the RDS Proxy pool and the API task count"
        namespace   = "AWS/RDS"
        metric      = "DatabaseConnections"
        dimensions  = { DBInstanceIdentifier = var.rds_instance_id }
        statistic   = "Maximum"
        period      = 300
        evaluations = 2
        threshold   = floor(coalesce(var.rds_max_connections, 0) * var.rds_connections_percent / 100)
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
      }
    },
    !local.has_optimization ? {} : {
      optimization-runtime-max = {
        description = "An optimization execution took > ${var.optimization_max_minutes} minutes (large-run limit) - check the SageMaker job size and optimizer_instance_type"
        namespace   = "AWS/States"
        metric      = "ExecutionTime"
        dimensions  = { StateMachineArn = local.optimization_sm }
        statistic   = "Maximum"
        period      = 300
        evaluations = 1
        threshold   = var.optimization_max_minutes * 60000
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
      }
    },
    # Daily datapoints: alarm after model_refresh_overdue_days days in a row without a success.
    !local.has_model_refresh || var.model_refresh_overdue_days == null ? {} : {
      model-refresh-overdue = {
        description = "No model refresh succeeded in ${coalesce(var.model_refresh_overdue_days, 0)} days - training data or models are stale (runbooks/model-refresh-failed.md)"
        namespace   = "AWS/States"
        metric      = "ExecutionsSucceeded"
        dimensions  = { StateMachineArn = local.model_refresh_sm }
        statistic   = "Sum"
        period      = 86400
        evaluations = coalesce(var.model_refresh_overdue_days, 1)
        threshold   = 1
        operator    = "LessThanThreshold"
        missing     = "breaching"
      }
    },
    { for k, arn in var.certificate_arns : "cert-expiry-${k}" => {
      description = "ACM certificate ${k} expires in < ${var.certificate_days_to_expiry} days (renewal is failing - check DNS validation)"
      namespace   = "AWS/CertificateManager"
      metric      = "DaysToExpiry"
      dimensions  = { CertificateArn = arn }
      statistic   = "Minimum"
      period      = 86400
      evaluations = 1
      threshold   = var.certificate_days_to_expiry
      operator    = "LessThanThreshold"
      missing     = "notBreaching"
    } },
  )
}

resource "aws_cloudwatch_metric_alarm" "simple" {
  for_each = local.simple_alarms

  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluations
  threshold           = each.value.threshold
  comparison_operator = each.value.operator
  treat_missing_data  = each.value.missing
  alarm_actions       = local.actions
  ok_actions          = local.actions

  tags = local.tags
}

# API 5xx rate (target + load balancer errors) over requests, only when there is real traffic.
resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  alarm_name          = "${var.name_prefix}-api-5xx-rate"
  alarm_description   = "API 5xx > ${var.api_5xx_percent_threshold}% of requests in 3 of 5 minutes"
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.api_5xx_percent_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "rate"
    expression  = "IF(requests >= ${var.api_5xx_min_requests}, 100 * (FILL(target5xx, 0) + FILL(elb5xx, 0)) / requests, 0)"
    label       = "5xx %"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = {
      requests  = { metric = "RequestCount", dimensions = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffixes["api"] } }
      target5xx = { metric = "HTTPCode_Target_5XX_Count", dimensions = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffixes["api"] } }
      elb5xx    = { metric = "HTTPCode_ELB_5XX_Count", dimensions = { LoadBalancer = var.alb_arn_suffix } }
    }

    content {
      id = metric_query.key

      metric {
        namespace   = "AWS/ApplicationELB"
        metric_name = metric_query.value.metric
        dimensions  = metric_query.value.dimensions
        stat        = "Sum"
        period      = 60
      }
    }
  }

  tags = local.tags
}

# Hourly share of ALB requests (UI + API) without a 5xx; quiet hours (< availability_min_requests) count as 100 %.
resource "aws_cloudwatch_metric_alarm" "availability" {
  alarm_name          = "${var.name_prefix}-availability"
  alarm_description   = "Availability < ${var.availability_target_percent}% in the last hour (5xx from the targets or the ALB)"
  evaluation_periods  = 1
  threshold           = var.availability_target_percent
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  metric_query {
    id          = "availability"
    expression  = "IF(requests >= ${var.availability_min_requests}, 100 - 100 * (FILL(target5xx, 0) + FILL(elb5xx, 0)) / requests, 100)"
    label       = "Availability %"
    return_data = true
  }

  dynamic "metric_query" {
    for_each = { requests = "RequestCount", target5xx = "HTTPCode_Target_5XX_Count", elb5xx = "HTTPCode_ELB_5XX_Count" }

    content {
      id = metric_query.key

      metric {
        namespace   = "AWS/ApplicationELB"
        metric_name = metric_query.value
        dimensions  = { LoadBalancer = var.alb_arn_suffix }
        stat        = "Sum"
        period      = 3600
      }
    }
  }

  tags = local.tags
}

# Published by the API, which runs the interactive what-if on the approved response curves
# (Embedded Metric Format, see README "App metric contract").
resource "aws_cloudwatch_metric_alarm" "whatif_latency" {
  alarm_name          = "${var.name_prefix}-whatif-p95"
  alarm_description   = "What-if simulation p95 > ${var.whatif_p95_ms / 1000}s for 3 of 5 minutes"
  namespace           = var.app_metric_namespace
  metric_name         = "WhatIfDurationMs"
  dimensions          = { Environment = var.environment }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.whatif_p95_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  tags = local.tags
}

# Published by the results publisher for every finished run (README "App metric contract").
resource "aws_cloudwatch_metric_alarm" "optimization_standard" {
  count = local.has_optimization ? 1 : 0

  alarm_name          = "${var.name_prefix}-optimization-standard-p95"
  alarm_description   = "Standard optimization runs p95 > ${var.optimization_standard_p95_seconds}s for 3 of 6 periods of 5 minutes"
  namespace           = var.app_metric_namespace
  metric_name         = "OptimizeDurationMs"
  dimensions          = { Environment = var.environment, RunSize = "standard" }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 6
  datapoints_to_alarm = 3
  threshold           = var.optimization_standard_p95_seconds * 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  tags = local.tags
}

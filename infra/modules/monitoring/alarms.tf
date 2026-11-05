locals {
  actions = [aws_sns_topic.alerts.arn]

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
      aurora-cpu = {
        description = "Aurora CPU > ${var.aurora_cpu_percent}% for 15 minutes"
        namespace   = "AWS/RDS"
        metric      = "CPUUtilization"
        dimensions  = { DBClusterIdentifier = var.aurora_cluster_id }
        statistic   = "Average"
        period      = 300
        evaluations = 3
        threshold   = var.aurora_cpu_percent
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
      }
      aurora-acu-max = {
        description = "Aurora Serverless at > ${var.aurora_acu_percent}% of its maximum ACU for 15 minutes - raise aurora_max_acu"
        namespace   = "AWS/RDS"
        metric      = "ACUUtilization"
        dimensions  = { DBClusterIdentifier = var.aurora_cluster_id }
        statistic   = "Average"
        period      = 300
        evaluations = 3
        threshold   = var.aurora_acu_percent
        operator    = "GreaterThanThreshold"
        missing     = "notBreaching"
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

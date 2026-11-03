locals {
  alb_dims = ["LoadBalancer", var.alb_arn_suffix]
  tg_dims  = ["TargetGroup", var.api_target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix]

  widgets = concat(
    [
      { title = "API requests and 5xx", metrics = [
        ["AWS/ApplicationELB", "RequestCount", local.tg_dims[0], local.tg_dims[1], local.tg_dims[2], local.tg_dims[3], { stat = "Sum" }],
        [".", "HTTPCode_Target_5XX_Count", ".", ".", ".", ".", { stat = "Sum" }],
        [".", "HTTPCode_ELB_5XX_Count", local.alb_dims[0], local.alb_dims[1], { stat = "Sum" }],
      ] },
      { title = "API latency (p50 / p95 / p99, s)", metrics = [
        ["AWS/ApplicationELB", "TargetResponseTime", local.tg_dims[0], local.tg_dims[1], local.tg_dims[2], local.tg_dims[3], { stat = "p50" }],
        ["...", { stat = "p95" }],
        ["...", { stat = "p99" }],
      ] },
      { title = "ECS CPU % per service", metrics = [
        for s in var.ecs_service_names : ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", s, { stat = "Average" }]
      ] },
      { title = "ECS running tasks per service", metrics = [
        for s in var.ecs_service_names : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", s, { stat = "Average" }]
      ] },
      { title = "Job queue (waiting, in flight, DLQ)", metrics = [
        ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.queue_name, { stat = "Maximum" }],
        [".", "ApproximateNumberOfMessagesNotVisible", ".", ".", { stat = "Maximum" }],
        [".", "ApproximateNumberOfMessagesVisible", ".", var.dlq_name, { stat = "Maximum", label = "DLQ" }],
      ] },
      { title = "Oldest job age (s)", metrics = [
        ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.queue_name, { stat = "Maximum" }],
      ] },
      { title = "What-if and optimizer duration (ms, p95)", metrics = [
        [var.app_metric_namespace, "WhatIfDurationMs", "Environment", var.environment, { stat = "p95" }],
        [".", "OptimizeDurationMs", ".", ".", { stat = "p95" }],
      ] },
      { title = "RDS CPU % and connections", metrics = [
        ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }],
        [".", "DatabaseConnections", ".", ".", { stat = "Maximum", yAxis = "right" }],
      ] },
      { title = "RDS free storage (bytes)", metrics = [
        ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Minimum" }],
      ] },
      { title = "Redis engine CPU % and memory %", metrics = concat(
        [for n in var.redis_node_ids : ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", n, { stat = "Average" }]],
        [for n in var.redis_node_ids : ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", n, { stat = "Maximum" }]],
      ) },
    ],
    var.waf_web_acl_name == null ? [] : [
      { title = "WAF allowed / blocked (us-east-1)", region = "us-east-1", metrics = [
        ["AWS/WAFV2", "AllowedRequests", "WebACL", var.waf_web_acl_name, "Rule", "ALL", { stat = "Sum" }],
        [".", "BlockedRequests", ".", ".", ".", ".", { stat = "Sum" }],
      ] },
    ],
    var.cloudfront_distribution_id == null ? [] : [
      { title = "CloudFront 4xx / 5xx % (us-east-1)", region = "us-east-1", metrics = [
        ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global", { stat = "Average" }],
        [".", "5xxErrorRate", ".", ".", ".", ".", { stat = "Average" }],
      ] },
    ],
  )
}

resource "aws_cloudwatch_dashboard" "platform" {
  dashboard_name = "${var.name_prefix}-platform"
  dashboard_body = jsonencode({
    widgets = concat(
      [{
        type   = "alarm"
        x      = 0
        y      = 0
        width  = 24
        height = 4
        properties = {
          title  = "Alarms"
          alarms = concat([for a in aws_cloudwatch_metric_alarm.simple : a.arn], [aws_cloudwatch_metric_alarm.api_5xx_rate.arn, aws_cloudwatch_metric_alarm.whatif_latency.arn])
        }
      }],
      [for i, w in local.widgets : {
        type   = "metric"
        x      = (i % 3) * 8
        y      = 4 + floor(i / 3) * 6
        width  = 8
        height = 6
        properties = {
          title   = w.title
          region  = lookup(w, "region", local.region)
          metrics = w.metrics
          view    = "timeSeries"
          stacked = false
          period  = 60
        }
      }],
    )
  })
}

locals {
  alb_dims = ["LoadBalancer", var.alb_arn_suffix]
  api_tg   = var.target_group_arn_suffixes["api"]
  ui_tg    = lookup(var.target_group_arn_suffixes, "ui", null)

  dashboard_alarm_arns = concat(
    [for a in aws_cloudwatch_metric_alarm.simple : a.arn],
    [aws_cloudwatch_metric_alarm.api_5xx_rate.arn, aws_cloudwatch_metric_alarm.availability.arn, aws_cloudwatch_metric_alarm.whatif_latency.arn],
    [for a in aws_cloudwatch_metric_alarm.optimization_standard : a.arn],
  )

  sfn_widgets = { for n, arn in var.state_machine_arns : n => [
    { title = "${n}: executions", metrics = [
      ["AWS/States", "ExecutionsStarted", "StateMachineArn", arn, { stat = "Sum" }],
      [".", "ExecutionsSucceeded", ".", ".", { stat = "Sum" }],
      [".", "ExecutionsFailed", ".", ".", { stat = "Sum" }],
      [".", "ExecutionsTimedOut", ".", ".", { stat = "Sum" }],
      [".", "ExecutionThrottled", ".", ".", { stat = "Sum" }],
    ] },
    { title = "${n}: execution time (ms)", metrics = [
      ["AWS/States", "ExecutionTime", "StateMachineArn", arn, { stat = "p50" }],
      ["...", { stat = "p95" }],
      ["...", { stat = "Maximum" }],
    ] },
  ] }

  # One dashboard per audience (Step 9): platform overview, API/UI, optimization, training, RDS, cost, GenAI.
  dashboard_widgets = merge(
    {
      platform = concat(
        [
          { title = "Requests and 5xx (UI + API)", metrics = [
            ["AWS/ApplicationELB", "RequestCount", local.alb_dims[0], local.alb_dims[1], { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { stat = "Sum" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", ".", { stat = "Sum" }],
          ] },
          { title = "ECS running tasks per service", metrics = [
            for s in var.ecs_service_names : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", s, { stat = "Average" }]
          ] },
          { title = "RDS CPU % and connections", metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }],
            [".", "DatabaseConnections", ".", ".", { stat = "Maximum", yAxis = "right" }],
          ] },
          { title = "Step Functions executions (started / failed)", metrics = concat(
            [for n, arn in var.state_machine_arns : ["AWS/States", "ExecutionsStarted", "StateMachineArn", arn, { stat = "Sum", label = "${n} started" }]],
            [for n, arn in var.state_machine_arns : ["AWS/States", "ExecutionsFailed", "StateMachineArn", arn, { stat = "Sum", label = "${n} failed" }]],
          ) },
          { title = "Lambda invocations / errors", metrics = concat(
            [for f in var.lambda_function_names : ["AWS/Lambda", "Invocations", "FunctionName", f, { stat = "Sum" }]],
            [for f in var.lambda_function_names : ["AWS/Lambda", "Errors", "FunctionName", f, { stat = "Sum" }]],
          ) },
        ],
        var.waf_web_acl_name == null ? [] : [
          { title = "WAF allowed / blocked", metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", var.waf_web_acl_name, "Region", local.region, "Rule", "ALL", { stat = "Sum" }],
            [".", "BlockedRequests", ".", ".", ".", ".", ".", ".", { stat = "Sum" }],
          ] },
        ],
      )

      api-ui = concat(
        [
          { title = "API requests and 5xx", metrics = [
            ["AWS/ApplicationELB", "RequestCount", "TargetGroup", local.api_tg, "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", ".", ".", { stat = "Sum" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", ".", ".", { stat = "Sum" }],
          ] },
          { title = "API latency (p50 / p95 / p99, s)", metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", local.api_tg, "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }],
          ] },
        ],
        local.ui_tg == null ? [] : [
          { title = "UI requests and 5xx", metrics = [
            ["AWS/ApplicationELB", "RequestCount", "TargetGroup", local.ui_tg, "LoadBalancer", var.alb_arn_suffix, { stat = "Sum" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", ".", ".", { stat = "Sum" }],
          ] },
        ],
        [
          { title = "ECS CPU % per service", metrics = [
            for s in var.ecs_service_names : ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", s, { stat = "Average" }]
          ] },
          { title = "ECS memory % per service", metrics = [
            for s in var.ecs_service_names : ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", s, { stat = "Average" }]
          ] },
          { title = "What-if duration (ms, p95)", metrics = [
            [var.app_metric_namespace, "WhatIfDurationMs", "Environment", var.environment, { stat = "p95" }],
          ] },
        ],
      )

      rds = [
        { title = "CPU % and connections", metrics = [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }],
          [".", "DatabaseConnections", ".", ".", { stat = "Maximum", yAxis = "right" }],
        ] },
        { title = "Free storage and freeable memory (bytes)", metrics = [
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Minimum" }],
          [".", "FreeableMemory", ".", ".", { stat = "Minimum" }],
        ] },
        { title = "Read / write latency (s)", metrics = [
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }],
          [".", "WriteLatency", ".", ".", { stat = "Average" }],
        ] },
        { title = "Read / write IOPS", metrics = [
          ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.rds_instance_id, { stat = "Average" }],
          [".", "WriteIOPS", ".", ".", { stat = "Average" }],
        ] },
        { title = "RDS Proxy client connections", metrics = [
          ["AWS/RDS", "ClientConnections", "ProxyName", "${var.rds_instance_id}-proxy", { stat = "Maximum" }],
          [".", "DatabaseConnections", ".", ".", { stat = "Maximum" }],
        ] },
      ]

      # Billing metrics exist only in us-east-1 and need "Receive Billing Alerts" on in the account.
      cost = [
        { title = "Estimated charges this month (USD)", region = "us-east-1", period = 21600, metrics = [
          ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { stat = "Maximum" }],
        ] },
        { title = "Estimated charges by service (USD)", region = "us-east-1", period = 21600, metrics = [
          for s in ["AmazonECS", "AmazonRDS", "AmazonSageMaker", "AWSGlue", "AmazonEC2", "AmazonS3", "AmazonCloudWatch", "AWSLambda", "AmazonVPC"] :
          ["AWS/Billing", "EstimatedCharges", "ServiceName", s, "Currency", "USD", { stat = "Maximum", label = s }]
        ] },
      ]
    },
    local.has_optimization ? {
      optimization = concat(
        local.sfn_widgets["optimization"],
        [
          { title = "Run duration by size (ms, p95, app metric)", metrics = [
            [var.app_metric_namespace, "OptimizeDurationMs", "Environment", var.environment, "RunSize", "standard", { stat = "p95" }],
            [".", ".", ".", ".", ".", "large", { stat = "p95" }],
          ] },
        ],
        var.optimizer_task_family == null ? [] : [
          { title = "Optimizer tasks: CPU / memory used (Container Insights)", metrics = [
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", var.ecs_cluster_name, "TaskDefinitionFamily", var.optimizer_task_family, { stat = "Maximum" }],
            [".", "MemoryUtilized", ".", ".", ".", ".", { stat = "Maximum", yAxis = "right" }],
          ] },
          { title = "Optimizer tasks running", metrics = [
            ["ECS/ContainerInsights", "TaskCount", "ClusterName", var.ecs_cluster_name, "TaskDefinitionFamily", var.optimizer_task_family, { stat = "Maximum" }],
          ] },
        ],
        var.publisher_function_name == null ? [] : [
          { title = "Results publisher", metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.publisher_function_name, { stat = "Sum" }],
            [".", "Errors", ".", ".", { stat = "Sum" }],
            [".", "Duration", ".", ".", { stat = "p95", yAxis = "right" }],
          ] },
        ],
        var.run_queue_name == null ? [] : [
          { title = "Run queue: waiting requests and DLQ", metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.run_queue_name, { stat = "Maximum", label = "waiting" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", coalesce(var.run_dlq_name, "${var.run_queue_name}-dlq"), { stat = "Maximum", label = "DLQ" }],
          ] },
          { title = "Run queue: oldest request (s)", metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.run_queue_name, { stat = "Maximum" }],
          ] },
          { title = "Running runs and expired requests", metrics = [
            ["MMM/Optimization", "RunningRuns", "StateMachine", "${var.name_prefix}-optimization", { stat = "Maximum" }],
            [".", "ExpiredRunRequests", ".", ".", { stat = "Sum", yAxis = "right" }],
          ] },
        ],
      )
    } : {},
    local.has_model_refresh ? {
      training = concat(
        local.sfn_widgets["model-refresh"],
        try(local.sfn_widgets["model-monitor"], []),
        length(var.drift_business_units) == 0 ? [] : [
          { title = "Model drift score per business unit", period = 86400, metrics = [
            for bu in var.drift_business_units : ["MMM/Models", "ModelDrift", "BusinessUnit", bu, "Check", "overall", { stat = "Maximum", label = bu }]
          ] },
        ],
      )
    } : {},
    # Glue jobs publish job metrics with --enable-metrics (set by the glue module).
    length(var.glue_job_names) == 0 ? {} : {
      data-pipeline = concat(
        [
          { title = "Glue jobs: elapsed time per run (s)", period = 3600, metrics = [
            for j in var.glue_job_names : ["Glue", "glue.driver.aggregate.elapsedTime", "JobName", j, "JobRunId", "ALL", "Type", "count", { stat = "Maximum", label = j }]
          ] },
          { title = "Glue jobs: failed tasks", period = 3600, metrics = [
            for j in var.glue_job_names : ["Glue", "glue.driver.aggregate.numFailedTasks", "JobName", j, "JobRunId", "ALL", "Type", "count", { stat = "Sum", label = j }]
          ] },
          { title = "Glue jobs: records read", period = 3600, metrics = [
            for j in var.glue_job_names : ["Glue", "glue.driver.aggregate.recordsRead", "JobName", j, "JobRunId", "ALL", "Type", "count", { stat = "Sum", label = j }]
          ] },
        ],
        var.databricks_export_function_name == null ? [] : [
          { title = "Databricks export Lambda", metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.databricks_export_function_name, { stat = "Sum" }],
            [".", "Errors", ".", ".", { stat = "Sum" }],
            [".", "Duration", ".", ".", { stat = "p95", yAxis = "right" }],
          ] },
        ],
        try(local.sfn_widgets["model-refresh"], []),
      )
    },
    var.llm_gateway_api_name == null ? {} : {
      genai = concat(
        [
          { title = "LLM gateway requests and errors", metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", var.llm_gateway_api_name, "Stage", "v1", { stat = "Sum" }],
            [".", "4XXError", ".", ".", ".", ".", { stat = "Sum" }],
            [".", "5XXError", ".", ".", ".", ".", { stat = "Sum" }],
          ] },
          { title = "LLM gateway latency (ms)", metrics = [
            ["AWS/ApiGateway", "Latency", "ApiName", var.llm_gateway_api_name, "Stage", "v1", { stat = "p50" }],
            ["...", { stat = "p95" }],
          ] },
        ],
        length(var.genai_business_units) == 0 ? [] : [
          { title = "GenAI tokens per business unit (app metric)", period = 3600, metrics = [
            for bu in var.genai_business_units : [var.app_metric_namespace, "GenAITokens", "Environment", var.environment, "BusinessUnit", bu, { stat = "Sum", label = bu }]
          ] },
        ],
      )
    },
  )

  dashboard_bodies = { for name, widgets in local.dashboard_widgets : name => jsonencode({
    widgets = concat(
      name == "platform" ? [{
        type       = "alarm"
        x          = 0
        y          = 0
        width      = 24
        height     = 4
        properties = { title = "Alarms", alarms = local.dashboard_alarm_arns }
      }] : [],
      [for i, w in widgets : {
        type   = "metric"
        x      = (i % 3) * 8
        y      = (name == "platform" ? 4 : 0) + floor(i / 3) * 6
        width  = 8
        height = 6
        properties = {
          title   = w.title
          region  = lookup(w, "region", local.region)
          metrics = w.metrics
          view    = "timeSeries"
          stacked = false
          period  = lookup(w, "period", 60)
        }
      }],
    )
  }) }
}

resource "aws_cloudwatch_dashboard" "this" {
  for_each = local.dashboard_bodies

  dashboard_name = "${var.name_prefix}-${each.key}"
  dashboard_body = each.value
}

moved {
  from = aws_cloudwatch_dashboard.platform
  to   = aws_cloudwatch_dashboard.this["platform"]
}

locals {
  scaling     = var.create_service && var.autoscaling != null
  cpu_scaling = local.scaling && try(var.autoscaling.type == "cpu", false)
  sqs_scaling = local.scaling && try(var.autoscaling.type == "sqs", false)
}

resource "aws_appautoscaling_target" "this" {
  count = local.scaling ? 1 : 0

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this[0].name}"
  min_capacity       = var.autoscaling.min
  max_capacity       = var.autoscaling.max

  tags = local.tags
}

# ------------------------------------------------------------------ API: CPU target tracking
resource "aws_appautoscaling_policy" "cpu" {
  count = local.cpu_scaling ? 1 : 0

  name               = "${local.full_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.cpu_target
    scale_out_cooldown = 60
    scale_in_cooldown  = 300

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# ------------------------------------------------------------------ Workers: SQS backlog step scaling
resource "aws_appautoscaling_policy" "scale_out" {
  count = local.sqs_scaling ? 1 : 0

  name               = "${local.full_name}-backlog-out"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    # Bounds are relative to the alarm threshold (messages waiting).
    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 10
      scaling_adjustment          = 1
    }

    step_adjustment {
      metric_interval_lower_bound = 10
      metric_interval_upper_bound = 50
      scaling_adjustment          = 3
    }

    step_adjustment {
      metric_interval_lower_bound = 50
      scaling_adjustment          = 5
    }
  }
}

# Back to min only when nothing is waiting and nothing is in flight; running jobs are also
# protected by ECS task scale-in protection, which the worker sets while it works.
resource "aws_appautoscaling_policy" "scale_in" {
  count = local.sqs_scaling ? 1 : 0

  name               = "${local.full_name}-backlog-in"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = 300
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = var.autoscaling.min
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_out" {
  count = local.sqs_scaling ? 1 : 0

  alarm_name          = "${local.full_name}-backlog-high"
  alarm_description   = "Jobs waiting in ${var.autoscaling.queue_name} - scale ${local.full_name} out"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.autoscaling.queue_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.autoscaling.scale_out_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_appautoscaling_policy.scale_out[0].arn]

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "scale_in" {
  count = local.sqs_scaling ? 1 : 0

  alarm_name          = "${local.full_name}-backlog-empty"
  alarm_description   = "${var.autoscaling.queue_name} empty and nothing in flight for 5 min - scale ${local.full_name} to min"
  evaluation_periods  = 5
  threshold           = 0
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_appautoscaling_policy.scale_in[0].arn]

  metric_query {
    id          = "backlog"
    expression  = "visible + inflight"
    label       = "Visible + in-flight messages"
    return_data = true
  }

  metric_query {
    id = "visible"

    metric {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesVisible"
      dimensions  = { QueueName = var.autoscaling.queue_name }
      stat        = "Maximum"
      period      = 60
    }
  }

  metric_query {
    id = "inflight"

    metric {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      dimensions  = { QueueName = var.autoscaling.queue_name }
      stat        = "Maximum"
      period      = 60
    }
  }

  tags = local.tags
}

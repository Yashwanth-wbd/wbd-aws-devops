# Event-driven alerts: things that are an event, not a metric crossing a threshold.
locals {
  service_arn_prefix = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.ecs_cluster_name}/"

  event_rules = merge(
    {
      ecs-deployment-failed = {
        description = "ECS deployment failed - the circuit breaker rolled the service back"
        pattern = {
          source        = ["aws.ecs"]
          "detail-type" = ["ECS Deployment State Change"]
          resources     = [{ prefix = local.service_arn_prefix }]
          detail        = { eventName = ["SERVICE_DEPLOYMENT_FAILED"] }
        }
        message = "\"ECS deployment FAILED and was rolled back: <resource>. Reason: <reason>\""
        paths   = { resource = "$.resources[0]", reason = "$.detail.reason" }
      }
      ecs-service-error = {
        description = "ECS service cannot start or place tasks (image pull, secrets, capacity)"
        pattern = {
          source        = ["aws.ecs"]
          "detail-type" = ["ECS Service Action"]
          resources     = [{ prefix = local.service_arn_prefix }]
          detail        = { eventType = ["ERROR"] }
        }
        message = "\"ECS service ERROR on <resource>: <event>\""
        paths   = { resource = "$.resources[0]", event = "$.detail.eventName" }
      }
    },
    var.enable_guardduty_alerts ? {
      guardduty-high = {
        description = "GuardDuty finding with severity >= 7 in this account"
        pattern = {
          source        = ["aws.guardduty"]
          "detail-type" = ["GuardDuty Finding"]
          detail        = { severity = [{ numeric = [">=", 7] }] }
        }
        message = "\"GuardDuty HIGH (<severity>): <type> - <title>\""
        paths   = { severity = "$.detail.severity", type = "$.detail.type", title = "$.detail.title" }
      }
    } : {},
  )
}

resource "aws_cloudwatch_event_rule" "alert" {
  for_each = local.event_rules

  name          = "${var.name_prefix}-${each.key}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "alert" {
  for_each = local.event_rules

  rule      = aws_cloudwatch_event_rule.alert[each.key].name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths    = each.value.paths
    input_template = each.value.message
  }
}

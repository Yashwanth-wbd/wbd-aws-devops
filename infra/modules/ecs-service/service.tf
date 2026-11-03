resource "aws_ecs_service" "this" {
  count = var.create_service ? 1 : 0

  name                    = local.full_name
  cluster                 = var.cluster_name
  task_definition         = aws_ecs_task_definition.this.arn
  desired_count           = var.desired_count
  platform_version        = "LATEST"
  enable_execute_command  = var.enable_execute_command
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  # Rolling update: start new tasks first (max 200 %), never drop below 100 %, roll back automatically.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  # Fargate spreads tasks across the subnets (AZs) given here.
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]

    content {
      target_group_arn = var.target_group_arn
      container_name   = "app"
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = var.target_group_arn == null ? null : 60

  dynamic "service_connect_configuration" {
    for_each = var.service_connect_namespace_arn == null ? [] : [1]

    content {
      enabled   = true
      namespace = var.service_connect_namespace_arn
    }
  }

  tags = local.tags

  # The deploy pipeline registers new task definitions and autoscaling owns the task count.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_iam_role_policy.app]
}

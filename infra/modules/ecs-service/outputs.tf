output "service_name" {
  description = "ECS service name (null for task-only definitions)."
  value       = one(aws_ecs_service.this[*].name)
}

output "task_definition_family" {
  description = "Task definition family."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "Seed task definition ARN (the pipeline registers newer revisions)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_role_arn" {
  description = "Task role ARN."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Task role name."
  value       = aws_iam_role.task.name
}

output "log_group_name" {
  description = "Service log group."
  value       = aws_cloudwatch_log_group.this.name
}

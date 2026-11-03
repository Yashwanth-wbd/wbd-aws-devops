output "budget_name" {
  description = "Monthly budget name."
  value       = aws_budgets_budget.monthly.name
}

output "anomaly_monitor_arn" {
  description = "Cost anomaly monitor ARN, or null when disabled."
  value       = var.enable_anomaly_detection ? aws_ce_anomaly_monitor.services[0].arn : null
}

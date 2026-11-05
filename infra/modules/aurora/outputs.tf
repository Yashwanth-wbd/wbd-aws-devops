output "cluster_identifier" {
  description = "Cluster identifier (<name_prefix>-aurora)."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "writer_endpoint" {
  description = "Cluster writer endpoint (clients use the proxy endpoint instead)."
  value       = aws_rds_cluster.this.endpoint
}

output "instance_identifiers" {
  description = "Cluster instance identifiers."
  value       = [for i in aws_rds_cluster_instance.this : i.identifier]
}

output "db_name" {
  description = "Initial database name."
  value       = aws_rds_cluster.this.database_name
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.this.port
}

output "master_user_secret_arn" {
  description = "RDS-managed admin secret (rotated by RDS)."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint - the DB_HOST for every task and the publisher Lambda."
  value       = aws_db_proxy.this.endpoint
}

output "proxy_arn" {
  description = "RDS Proxy ARN."
  value       = aws_db_proxy.this.arn
}

output "proxy_resource_id" {
  description = "prx-... ID used in rds-db:connect ARNs: arn:aws:rds-db:<region>:<account>:dbuser:<proxy_resource_id>/<db_user>."
  value       = element(split(":", aws_db_proxy.this.arn), 6)
}

output "log_group_name" {
  description = "PostgreSQL log group (connections, errors and pgaudit)."
  value       = aws_cloudwatch_log_group.this.name
}

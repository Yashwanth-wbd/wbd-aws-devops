output "replication_group_id" {
  description = "Replication group ID."
  value       = aws_elasticache_replication_group.this.id
}

output "primary_endpoint" {
  description = "Primary endpoint (TLS, port 6379) - REDIS_HOST for API and workers."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint (same as primary when there is a single node)."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port."
  value       = aws_elasticache_replication_group.this.port
}

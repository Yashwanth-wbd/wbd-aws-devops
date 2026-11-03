output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "AZs used, in subnet order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnets (ALB, NAT)."
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "private_app_subnet_ids" {
  description = "Private-app subnets (ECS tasks, MWAA)."
  value       = [for az in local.azs : aws_subnet.app[az].id]
}

output "private_data_subnet_ids" {
  description = "Private-data subnets (RDS, RDS Proxy, ElastiCache); no internet route."
  value       = [for az in local.azs : aws_subnet.data[az].id]
}

output "private_endpoint_subnet_ids" {
  description = "Private-endpoint subnets (interface endpoints, resolver, TGW attachment)."
  value       = [for az in local.azs : aws_subnet.endpoint[az].id]
}

output "route_table_ids" {
  description = "Route table IDs per tier."
  value = {
    public   = aws_route_table.public.id
    app      = [for az in local.azs : aws_route_table.app[az].id]
    data     = aws_route_table.data.id
    endpoint = aws_route_table.endpoint.id
  }
}

output "nat_public_ips" {
  description = "NAT gateway public IPs (give to third parties that allow-list our egress)."
  value       = [for e in aws_eip.nat : e.public_ip]
}

output "security_group_ids" {
  description = "Security group ID per role: endpoints, alb, api, workers, data_clients, rds_proxy, rds, redis (+ mwaa, resolver when enabled)."
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}

output "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint (for egress rules)."
  value       = aws_vpc_endpoint.gateway["s3"].prefix_list_id
}

output "interface_endpoint_ids" {
  description = "Interface endpoint ID per service."
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
}

output "flow_log_group_name" {
  description = "CloudWatch log group of the VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "transit_gateway_attachment_id" {
  description = "TGW attachment ID (null when disabled)."
  value       = one(aws_ec2_transit_gateway_vpc_attachment.this[*].id)
}

output "resolver_endpoint_id" {
  description = "Resolver outbound endpoint ID (null when disabled)."
  value       = one(aws_route53_resolver_endpoint.outbound[*].id)
}

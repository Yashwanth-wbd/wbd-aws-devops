output "policy_arn" {
  description = "ARN to pass as permissions_boundary on every IAM role."
  value       = aws_iam_policy.boundary.arn
}

output "policy_name" {
  description = "Boundary policy name."
  value       = aws_iam_policy.boundary.name
}

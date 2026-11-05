output "user_pool_id" {
  description = "User pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "User pool ARN (ALB authenticate-cognito)."
  value       = aws_cognito_user_pool.this.arn
}

output "client_id" {
  description = "ALB app client ID (public value)."
  value       = aws_cognito_user_pool_client.alb.id
}

output "domain_prefix" {
  description = "Hosted domain prefix (ALB authenticate-cognito user_pool_domain)."
  value       = aws_cognito_user_pool_domain.this.domain
}

output "issuer" {
  description = "Token issuer URL."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "logout_url" {
  description = "Sign-out URL the UI redirects to after the ALB session cookie is cleared."
  value       = "https://${local.domain_host}/logout?client_id=${aws_cognito_user_pool_client.alb.id}&logout_uri=${urlencode("${local.app_url}/")}"
}

output "okta_app_settings" {
  description = "Values WBD enters in the Okta SAML app of this environment (docs/04)."
  value = {
    single_sign_on_url = "https://${local.domain_host}/saml2/idpresponse"
    audience_uri       = "urn:amazon:cognito:sp:${aws_cognito_user_pool.this.id}"
    name_id_format     = "Persistent"
    attributes         = [var.saml_attribute_email, var.saml_attribute_name]
    group_attribute    = var.saml_attribute_groups
  }
}

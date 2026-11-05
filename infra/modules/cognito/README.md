# cognito

Cognito user pool federated to **WBD Okta (SAML)**, used by the ALB `authenticate-cognito`
action. Users never get a Cognito password: they sign in at Okta (MFA there), and the ALB keeps
the session in the `mmm-session` cookie. Details in [docs/04](../../../docs/04-okta-mfa-app-login.md).

**Status:** implemented (v2 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_cognito_user_pool` `<prefix>-users` | Self sign-up off (`allow_admin_create_user_only`); users are created on first federated login. Custom attribute `custom:groups` (Okta groups) |
| `aws_cognito_identity_provider` `WBD-Okta` | SAML, metadata from `saml_metadata_url` (public URL, no secret). Maps `email`, `name`, `groups` |
| `aws_cognito_user_pool_domain` | `<domain_prefix>.auth.<region>.amazoncognito.com` |
| `aws_cognito_user_pool_client` `alb` | Confidential client (secret generated, read only by the ALB), code flow, scopes `openid email profile`, callback `https://<app_domain_name>/oauth2/idpresponse`, refresh token `session_hours` |

## Inputs

`name_prefix`, `app_domain_name`, `domain_prefix`, `idp_name`, `saml_metadata_url`,
`saml_attribute_email` / `_name` / `_groups`, `session_hours` (12), `deletion_protection`, `tags`.

## Outputs

`user_pool_id`, `user_pool_arn`, `client_id`, `domain_prefix`, `issuer`, `logout_url`,
`okta_app_settings` (ACS URL and audience URI that WBD enters in the Okta SAML app).

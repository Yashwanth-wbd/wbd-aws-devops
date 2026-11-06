# alb

The internet-facing Application Load Balancer – the single front door of the app. It signs users
in directly with **WBD Okta (OIDC)** and routes to the `ui` and `api` ECS services. The regional
WAF (`waf-regional` module) is attached to it.

**Status:** implemented (v3 architecture: Okta at the ALB replaces the v2 Cognito sign-in).

## What it creates

| Resource | Name | Notes |
|---|---|---|
| ALB | `<prefix>-alb` | Public subnets, `alb` security group (443/80 from `alb_ingress_cidrs`). Drops invalid header fields; desync mitigation `strictest`; access logs to the log bucket under `alb/`; deletion protection on by default |
| Target groups | `<prefix>-ui-tg`, `<prefix>-api-tg` | Target type `ip` (Fargate). Health checks: ui `ui_health_check_path` (`/healthz`) on `ui_port`, api `health_check_path` (`/api/health`) on `app_port`, expecting `200` |
| HTTP listener (80) | – | Redirect 301 to HTTPS only |
| HTTPS listener (443) | – | TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`. **Default:** `authenticate-oidc` with Okta (unauthenticated → redirect to Okta sign-in) then forward to `ui` |
| Rule priority 10 | – | `health_check_path` → `api`, no sign-in (smoke tests, uptime checks) |
| Rule priority 20 | – | `/api/*` → `authenticate-oidc` with `on_unauthenticated_request = deny` (401 instead of a redirect, right for XHR), then forward to `api` |

## How the API knows the user

After sign-in the ALB adds `x-amzn-oidc-data` (a JWT signed by the ALB with the Okta user claims,
including `groups`), `x-amzn-oidc-identity` and `x-amzn-oidc-accesstoken` to every forwarded
request. The API must verify the JWT signature with the ALB public key for its region and check
that the `signer` field equals `ALB_ARN` (task environment). Session cookie: `mmm-session`,
lifetime `oidc.session_seconds`. Without `oidc` (null) the listener answers **503** on everything
except the health path, so a new environment is never reachable without sign-in (the stacks use this
until the Okta client secret is stored). `allow_unauthenticated = true` forwards without sign-in –
isolated tests only.

The ALB calls the Okta token and user-info endpoints itself, so the `alb` security group needs
outbound HTTPS to the internet (it has it; the ALB is in the public subnets).

## Okta app (WBD Identity team, one per environment)

OIDC **Web** application, grant type Authorization Code, sign-in redirect URI
`https://<app_domain_name>/oauth2/idpresponse`, sign-out redirect `https://<app_domain_name>/`,
`groups` claim in the ID token (filter `mmm-*`). The stack prints these values as
`terraform output okta_app_settings`. The client secret is stored in Secrets Manager
(`mmm/<env>/okta/alb-client`) and passed in as `oidc_client_secret` – it ends up only in the
encrypted Terraform state.

## Checkov skips (with reason)

| Check | Reason |
|---|---|
| `CKV_AWS_150` | Deletion protection is set per environment (`deletion_protection`, on in prod). |
| `CKV2_AWS_28` | The regional WAF is associated by the `waf-regional` module. |
| `CKV_AWS_378` | TLS ends at the ALB. ALB-to-task traffic stays in the VPC and is limited to the `alb` security group. |
| `CKV_AWS_2`, `CKV_AWS_103` | Port 80 only redirects to HTTPS. |

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix`, `vpc_id`, `public_subnet_ids`, `security_group_id` | – | From `network` |
| `certificate_arn` | – | ACM certificate in the same region as the ALB |
| `oidc` | `null` | `{ issuer, authorization_endpoint, token_endpoint, user_info_endpoint, client_id, scope = "openid profile email groups", session_seconds = 43200 }` |
| `oidc_client_secret` | `null` | Sensitive; from Secrets Manager |
| `allow_unauthenticated` | `false` | Without `oidc`: forward instead of 503 (tests only) |
| `app_port`, `ui_port` | `8080` | |
| `health_check_path` | `/api/health` | |
| `ui_health_check_path` | `/healthz` | |
| `access_log_bucket`, `access_log_prefix` | –, `alb` | `module.log_bucket` |
| `deletion_protection` | `true` | `false` in dev if you want `terraform destroy` to work |
| `idle_timeout` | `60` | |
| `tags` | `{}` | |

## Outputs

`alb_arn`, `alb_arn_suffix`, `alb_dns_name`, `alb_zone_id`, `target_group_arns` (map ui/api),
`target_group_arn_suffixes` (map), `https_listener_arn`.

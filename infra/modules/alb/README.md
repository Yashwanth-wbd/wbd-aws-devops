# alb

The **internal** Application Load Balancer – the single, private entry point of the app. There is
no public entry: the ALB sits in the private-app subnets and is reached only from the WBD network
(through the Transit Gateway). Every request is first authenticated with **WBD Okta (OIDC)**; only
then is it routed to the `ui` and `api` ECS services.

**Status:** implemented (v6 architecture: internal ALB, Okta first; no WAF, no Route 53, no API Gateway).

## What it creates

| Resource | Name | Notes |
|---|---|---|
| ALB | `<prefix>-alb` | Scheme `internal` (`internal = true`), private-app subnets, `alb` security group (443/80 from `alb_ingress_cidrs` = WBD ranges). Drops invalid header fields; desync mitigation `strictest`; access logs to the log bucket under `alb/`; deletion protection on by default |
| Target groups | `<prefix>-ui-tg`, `<prefix>-api-tg` | Target type `ip` (Fargate). Health checks: ui `ui_health_check_path` (`/healthz`) on `ui_port`, api `health_check_path` (`/api/health`) on `app_port`, expecting `200` |
| HTTP listener (80) | – | Redirect 301 to HTTPS only |
| HTTPS listener (443) | – | TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`. **Default:** `authenticate-oidc` with Okta (unauthenticated → redirect to Okta sign-in) then forward to `ui` |
| Rule priority 10 | – | `health_check_path` → `api`, no sign-in (smoke tests, uptime checks) |
| Rule priority 20 | – | `/api/*` → `authenticate-oidc` with `on_unauthenticated_request = deny` (401 instead of a redirect, right for XHR), then forward to `api` |

## Name and certificate

The app host name (e.g. `mmm-dev.<wbd-internal-domain>`) is a record in **WBD DNS** (outside AWS)
pointing to the ALB DNS name (`terraform output dns_records_for_wbd`); the stack creates no
Route 53 record. The certificate is an ACM certificate in the same region: DNS-validated, or
issued by the WBD private CA (ACM Private CA or imported).

## How the API knows the user

After sign-in the ALB adds `x-amzn-oidc-data` (a JWT signed by the ALB with the Okta user claims,
including `groups`), `x-amzn-oidc-identity` and `x-amzn-oidc-accesstoken` to every forwarded
request. The API must verify the JWT signature with the ALB public key for its region and check
that the `signer` field equals `ALB_ARN` (task environment). Session cookie: `mmm-session`,
lifetime `oidc.session_seconds`. Without `oidc` (null) the listener answers **503** on everything
except the health path, so a new environment is never reachable without sign-in (the stacks use this
until the Okta client secret is stored). `allow_unauthenticated = true` forwards without sign-in –
isolated tests only.

The browser is redirected to Okta and back (it reaches Okta itself). The ALB calls the Okta token
and user-info endpoints itself, so the `alb` security group needs outbound HTTPS (it has it; the
internal ALB reaches Okta through the NAT gateway, or the WBD egress through the Transit Gateway).

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
| `CKV2_AWS_28` | Internal ALB with no public entry; the architecture has no WAF (WBD ranges + Okta sign-in). |
| `CKV_AWS_378` | TLS ends at the ALB. ALB-to-task traffic stays in the VPC and is limited to the `alb` security group. |
| `CKV_AWS_2`, `CKV_AWS_103` | Port 80 only redirects to HTTPS. |

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix`, `vpc_id`, `subnet_ids`, `security_group_id` | – | From `network` (`subnet_ids` = private-app subnets) |
| `internal` | `true` | Internal scheme (private entry only) |
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

`alb_arn`, `alb_arn_suffix`, `internal`, `alb_dns_name`, `alb_zone_id`, `target_group_arns` (map ui/api),
`target_group_arn_suffixes` (map), `https_listener_arn`.

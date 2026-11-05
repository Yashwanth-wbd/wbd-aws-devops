# alb

The internet-facing Application Load Balancer – the single front door of the app. It signs users
in through Cognito (federated to WBD Okta) and routes to the `ui` and `api` ECS services. The
regional WAF (`waf-regional` module) is attached to it.

**Status:** implemented (v2 architecture; replaces CloudFront + origin-verify of v1).

## What it creates

| Resource | Name | Notes |
|---|---|---|
| ALB | `<prefix>-alb` | Public subnets, `alb` security group (443/80 from `alb_ingress_cidrs`). Drops invalid header fields; desync mitigation `strictest`; access logs to the log bucket under `alb/`; deletion protection on by default |
| Target groups | `<prefix>-ui-tg`, `<prefix>-api-tg` | Target type `ip` (Fargate). Health checks: ui `ui_health_check_path` (`/healthz`) on `ui_port`, api `health_check_path` (`/api/health`) on `app_port`, expecting `200` |
| HTTP listener (80) | – | Redirect 301 to HTTPS only |
| HTTPS listener (443) | – | TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`. **Default:** `authenticate-cognito` (unauthenticated → redirect to sign-in) then forward to `ui` |
| Rule priority 10 | – | `health_check_path` → `api`, no sign-in (smoke tests, uptime checks) |
| Rule priority 20 | – | `/api/*` → `authenticate-cognito` with `on_unauthenticated_request = deny` (401 instead of a redirect, right for XHR), then forward to `api` |

## How the API knows the user

After sign-in the ALB adds `x-amzn-oidc-data` (a JWT signed by the ALB with the user's claims,
including `custom:groups`) and `x-amzn-oidc-identity` to every forwarded request. The API must
verify the JWT signature with the ALB public key for its region and check that the `signer` field
equals `ALB_ARN` (task environment). Session cookie: `mmm-session`, lifetime `cognito.session_seconds`.
Without `cognito` (null) the listener forwards without authentication – only for a first smoke test.

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
| `cognito` | `null` | `{ user_pool_arn, client_id, domain_prefix, session_seconds = 43200 }` from `cognito` |
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

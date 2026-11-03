# alb

The internet-facing Application Load Balancer for the API. It sits behind CloudFront (Step 8).

**Status:** implemented in Step 7.

## What it creates

| Resource | Name | Notes |
|---|---|---|
| ALB | `<prefix>-alb` | In the public subnets with the `alb` security group. Drops invalid header fields; desync mitigation `strictest`; access logs go to the log bucket under `alb/`; deletion protection on by default. |
| Target group | `<prefix>-api-tg` | Target type `ip` (needed for Fargate), port `app_port`, health check `GET /api/health` expecting `200`. |
| HTTPS listener (443) | – | TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`, certificate `certificate_arn`. **Default action: fixed 403.** |
| Listener rule (priority 10) | – | Forwards to the target group **only if** the `X-Origin-Verify` header equals the `edge/origin-verify` secret. |

## Why a 403 by default

Only CloudFront knows the `X-Origin-Verify` value: Step 8 adds it as a custom origin header. A
request that goes straight to the ALB DNS name, bypassing CloudFront and its WAF, gets a 403.
There is no port-80 listener: CloudFront talks to the ALB over HTTPS only, and the `alb` security
group allows only 443 from the CloudFront origin-facing prefix list. Until Step 8 is applied, you can test by sending the header yourself (see the dev README).

The value is the generated secret `mmm/<env>/edge/origin-verify`. To rotate it, change
`generated_secret_rotation_id` in tfvars and apply. The ALB rule and CloudFront are updated in the
same apply.

## Checkov skips (with reason)

| Check | Reason |
|---|---|
| `CKV_AWS_150` | Deletion protection is set per environment (`deletion_protection`, on in prod). |
| `CKV2_AWS_28` | The WAF is attached to CloudFront (Step 8). The ALB accepts only CloudFront IPs plus the `X-Origin-Verify` header. |
| `CKV_AWS_378` | TLS ends at the ALB. ALB-to-task traffic stays in the VPC and is limited to the `alb` security group. |

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | |
| `vpc_id` | – | |
| `public_subnet_ids` | – | `module.network.subnet_ids["public"]` |
| `security_group_id` | – | `module.network.security_group_ids["alb"]` |
| `certificate_arn` | – | ACM certificate in the same region as the ALB |
| `origin_verify_value` | – | Sensitive. `module.secrets.generated_values["edge/origin-verify"]` |
| `app_port` | `8080` | |
| `health_check_path` | `/api/health` | |
| `access_log_bucket` | – | `module.log_bucket.bucket_name` |
| `access_log_prefix` | `alb` | |
| `deletion_protection` | `true` | Set `false` in dev if you want `terraform destroy` to work |
| `idle_timeout` | `60` | |
| `tags` | `{}` | |

## Outputs

`alb_arn`, `alb_arn_suffix`, `alb_dns_name`, `alb_zone_id`, `target_group_arn`, `target_group_arn_suffix`,
`https_listener_arn`.

# network

The VPC for one environment: four subnet tiers, NAT, VPC endpoints, one security group per
service role, VPC flow logs, and optional WBD hub connectivity (Transit Gateway and DNS
forwarding).

**Status:** implemented in Step 4.

## Files

| File | Contents |
|---|---|
| `main.tf` | VPC, default SG lock-down, IGW, subnets, NAT, route tables |
| `endpoints.tf` | Gateway endpoints (S3, DynamoDB) and interface endpoints |
| `security-groups.tf` | Security groups and their rules |
| `flow-logs.tf` | Flow log group (KMS), IAM role (with permission boundary), flow log |
| `hub.tf` | Optional Transit Gateway attachment + routes, Route 53 Resolver outbound endpoint + FORWARD rules |

## Subnet layout

The VPC CIDR is split into eight equal blocks. For the dev placeholder `10.40.0.0/19`:

| Tier | AZ 1 | AZ 2 | AZ 3 (staging/prod) | Route to internet | Used by |
|---|---|---|---|---|---|
| private-app | `10.40.0.0/22` | `10.40.4.0/22` | `10.40.8.0/22` | NAT gateway | ECS tasks, SageMaker jobs, Lambda functions |
| (spare) | `10.40.12.0/22` | | | – | 4th AZ / growth |
| public | `10.40.16.0/24` | `10.40.17.0/24` | `10.40.18.0/24` | Internet gateway | ALB, NAT only |
| private-data | `10.40.20.0/24` | `10.40.21.0/24` | `10.40.22.0/24` | **none** | RDS PostgreSQL, RDS Proxy |
| private-endpoint | `10.40.24.0/24` | `10.40.25.0/24` | `10.40.26.0/24` | **none** | Interface endpoints, resolver, TGW attachment |
| (spare) | `10.40.28.0/22` | | | – | growth |

- App subnets are the biggest because every Fargate task takes its own IP.
- Public subnets never assign public IPs (`map_public_ip_on_launch = false`).
- The data and endpoint tiers have only the VPC-local route. The data tier can also reach S3
  and DynamoDB through the gateway endpoints.
- AZs are chosen by **AZ ID** (`use1-az1`), not by name. An AZ ID is the same physical zone in
  every account, so dev, staging and prod line up, and the list never shifts on its own.

## NAT

| Environment | NAT gateways |
|---|---|
| dev | 1, shared by both AZs (`single_nat_gateway = true`) |
| staging / prod | 1 per AZ, so losing an AZ does not cut egress for the others |

If WBD sends all internet traffic through a central egress firewall, set
`enable_nat_gateway = false` and route `0.0.0.0/0` to the Transit Gateway in
`transit_gateway_routes`.

## VPC endpoints

- **Gateway endpoints (free):** S3 and DynamoDB, on the app and data route tables. ECR image
  layers are stored in S3, so image pulls do not go through NAT.
- **Interface endpoints (`interface_endpoints`):** `ecr.api`, `ecr.dkr`, `sts`, `secretsmanager`,
  `ssm`, `ssmmessages` (ECS Exec), `kms`, `logs`, `monitoring`, `xray`, `states` (Step Functions),
  `sagemaker.api`, `sqs` (optimization run queue). Through `additional_interface_endpoints`: `glue` (data platform), `execute-api`, `bedrock-runtime` (GenAI).
  - They sit in the endpoint subnets with private DNS, so the AWS SDK uses them automatically.
  - Cost is about USD 7.3 per endpoint per AZ per month, so around USD 175 a month in dev (12 endpoints × 2 AZs).

## Security groups

Names are `mmm-<env>-<role>-sg`. The default VPC security group has all its rules removed.

| SG | Inbound | Outbound | Attached in |
|---|---|---|---|
| `endpoints` | 443 from the VPC CIDR | – | this module |
| `alb` | 443 and 80 (redirect) from each `alb_ingress_cidrs` entry | app port → `api`, web port → `ui`, 443 → anywhere (Okta token and user info calls) | ALB |
| `api` | app port (`8080`) from `alb` | 443 → anywhere (AWS APIs, ALB signing keys) | API service |
| `ui` | web port (`ui_port`, `8080`) from `alb` | 443 → `endpoints`, 443 → S3 prefix list | UI service |
| `tasks` | none | 443 → anywhere | platform-check and DB bootstrap tasks |
| `data_clients` | none | 5432 → `rds_proxy`, 443 → `endpoints`, 443 → S3 prefix list | API, publisher Lambda, **migration task** |
| `rds_proxy` | 5432 from `data_clients` | 5432 → `rds` | RDS Proxy |
| `rds` | 5432 from `rds_proxy` | – | RDS PostgreSQL instance |
| `sagemaker` | all from itself | all to itself, 443 → `endpoints`, 443 → S3 prefix list | SageMaker jobs (no internet) |
| `lambda` | none | 443 → `endpoints`, 443 → S3 prefix list | results-publisher and run-dispatcher Lambdas |
| `optimizer` | none | 443 → `endpoints`, 443 → S3 prefix list | Optimizer ECS task (one per run; with `data_clients` only if the app needs the DB) |
| `glue` (optional) | all from itself | all to itself, 443 → `endpoints`, 443 → S3 prefix list | Glue job ENIs (Spark driver ↔ executors), with `data_clients` for export-rds |
| `databricks_export` (optional) | none | 443 → anywhere (Databricks workspace via NAT, or PrivateLink) | Databricks export Lambda |
| `genai` (optional) | none | 443 → anywhere (approved LLM providers) | LLM gateway proxy Lambda |
| `resolver` (optional) | – | 53 TCP/UDP → each WBD DNS IP | this module |

- Only resources that carry `data_clients` can reach the database, and only through RDS Proxy.
- The migration task gets `data_clients` alone. Its ID is the GitHub variable `DATA_CLIENTS_SG_ID`.
- `alb_ingress_cidrs` defaults to `0.0.0.0/0` (the WAF filters). Set it to the WBD corporate / VPN
  ranges if the app must not be reachable from the internet.

## Flow logs

- All VPC traffic, at 60-second aggregation, goes to `/aws/vpc/mmm-<env>/flow-logs`, encrypted
  with the `logs` KMS key.
- Retention comes from `flow_logs_retention_days`: dev 90 days, staging 180, prod 365.
- The role `mmm-<env>-vpc-flow-logs` can only write to that log group. Only VPC Flow Logs in
  this account can assume it, and it carries the permission boundary.

## WBD hub connectivity (optional, off by default)

| Feature | Switch | Inputs from WBD Network |
|---|---|---|
| Transit Gateway attachment in the endpoint subnets, plus routes from the app subnets | `enable_transit_gateway` | `transit_gateway_id` (shared to the account via AWS RAM), `transit_gateway_routes` |
| Route 53 Resolver outbound endpoint and FORWARD rules associated with the VPC | `enable_resolver_forwarding` | `resolver_forward_domains`, `resolver_target_ips` |

- The data subnets never get a Transit Gateway route.
- Preconditions stop the plan if a switch is on but its inputs are missing, or if
  `0.0.0.0/0` goes to the TGW while NAT is still on.
- If WBD shares resolver rules centrally through AWS RAM instead, leave the resolver switch off
  and only associate their shared rules.
- Databricks PrivateLink is in the `databricks-access` module (Step 13).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | string | – | e.g. `mmm-dev` |
| `vpc_cidr` | string | – | /19 or larger |
| `availability_zone_ids` | list(string) | – | 2 (dev) or 3 (staging/prod) AZ IDs |
| `enable_nat_gateway` | bool | `true` | false when WBD central egress is used |
| `single_nat_gateway` | bool | `false` | true in dev |
| `interface_endpoints` | list(string) | 13 services above | Interface endpoint suffixes |
| `app_port` | number | `8080` | API container port |
| `ui_port` | number | `8080` | UI container port |
| `alb_ingress_cidrs` | list(string) | `["0.0.0.0/0"]` | Ranges allowed to reach the ALB |
| `create_genai_security_group` | bool | `false` | Release 2: creates `genai` (no inbound, HTTPS out) |
| `create_data_platform_security_groups` | bool | `false` | Step 13: creates `glue` and `databricks_export` |
| `additional_interface_endpoints` | list(string) | `[]` | Extra endpoint suffixes (data platform adds `glue`; Release 2 adds `execute-api` and `bedrock-runtime`) |
| `flow_logs_retention_days` | number | `365` | Flow log retention |
| `logs_kms_key_arn` | string | – | `module.kms.key_arns["logs"]` |
| `permissions_boundary_arn` | string | – | `module.permission_boundary.policy_arn` |
| `enable_transit_gateway` / `transit_gateway_id` / `transit_gateway_routes` | | off | WBD hub |
| `enable_resolver_forwarding` / `resolver_forward_domains` / `resolver_target_ips` | | off | WBD DNS |
| `tags` | map(string) | `{}` | Extra tags |

## Outputs

`vpc_id`, `vpc_cidr`, `availability_zones`, `public_subnet_ids`, `private_app_subnet_ids`,
`private_data_subnet_ids`, `private_endpoint_subnet_ids`, `route_table_ids`, `nat_public_ips`,
`security_group_ids` (map by role), `s3_prefix_list_id`, `interface_endpoint_ids`,
`flow_log_group_name`, `transit_gateway_attachment_id`, `resolver_endpoint_id`.

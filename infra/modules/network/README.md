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
| private-app | `10.40.0.0/22` | `10.40.4.0/22` | `10.40.8.0/22` | NAT gateway | ECS tasks, MWAA |
| (spare) | `10.40.12.0/22` | | | – | 4th AZ / growth |
| public | `10.40.16.0/24` | `10.40.17.0/24` | `10.40.18.0/24` | Internet gateway | ALB, NAT only |
| private-data | `10.40.20.0/24` | `10.40.21.0/24` | `10.40.22.0/24` | **none** | RDS, RDS Proxy, ElastiCache |
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
  `ssm`, `ssmmessages` (ECS Exec), `kms`, `logs`, `monitoring`, `xray`, `sqs`.
  - They sit in the endpoint subnets with private DNS, so the AWS SDK uses them automatically.
  - Cost is about USD 7.3 per endpoint per AZ per month, so around USD 160 a month in dev.

## Security groups

Names are `mmm-<env>-<role>-sg`. The default VPC security group has all its rules removed.

| SG | Inbound | Outbound | Attached in |
|---|---|---|---|
| `endpoints` | 443 from the VPC CIDR | – | this module |
| `alb` | 443 from the CloudFront origin-facing prefix list | app port → `api` | Step 7 (ALB) |
| `api` | app port (`8080`) from `alb` | 443 → anywhere (AWS APIs, Okta), 6379 → `redis` | Step 7 (API service) |
| `workers` | none | 443 → anywhere (AWS APIs, Databricks), 6379 → `redis` | Step 7 (what-if, optimizer) |
| `data_clients` | none | 5432 → `rds_proxy`, 443 → `endpoints`, 443 → S3 prefix list | Step 7 (API, workers, **migration task**) |
| `rds_proxy` | 5432 from `data_clients` | 5432 → `rds` | Step 6 |
| `rds` | 5432 from `rds_proxy` | – | Step 6 |
| `redis` | 6379 from `api`, `workers` | – | Step 6 |
| `mwaa` (optional) | all from itself | all to itself, 443 → anywhere | Step 13 |
| `data_trigger` (optional) | none | 443 → anywhere (MWAA API) | Step 13, data-trigger Lambda |
| `resolver` (optional) | – | 53 TCP/UDP → each WBD DNS IP | this module |

- Only tasks that carry `data_clients` can reach the database, and only through RDS Proxy.
- The migration task gets `data_clients` alone. Its ID is the GitHub variable `DATA_CLIENTS_SG_ID`.
- The CloudFront prefix list ID is looked up by name, so no placeholder is needed. It counts as
  about 55 rules against the ALB SG quota, which is fine because that SG has one inbound rule.

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
| `interface_endpoints` | list(string) | 11 services above | Interface endpoint suffixes |
| `app_port` | number | `8080` | API container port |
| `create_mwaa_security_group` | bool | `false` | Step 13: creates `mwaa` and `data_trigger` |
| `create_genai_security_group` | bool | `false` | Step 14: creates `genai` (app port from `api` only; HTTPS to the endpoints SG and S3 prefix list only) and the `api` → `genai` egress rule |
| `additional_interface_endpoints` | list(string) | `[]` | Extra endpoint suffixes (Step 14 adds `ecs-agent` for the Service Connect proxy of the GenAI gateway) |
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

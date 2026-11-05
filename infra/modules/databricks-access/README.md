# databricks-access

Private, least-privilege access between this account and the **WBD-owned** Databricks workspace.

**Status:** implemented in Step 13 (created only when `enable_data_platform = true`).

## What it creates

| Resource | Notes |
|---|---|
| IAM role `mmm-<env>-databricks-uc` | Unity Catalog **storage credential**. Read/write on the landing, lakehouse and training-data buckets and their keys (s3 + per-BU keys). Permission boundary |
| VPC endpoint (Interface) | `enable_privatelink`: the workspace REST/UI endpoint service, in the private-endpoint subnets, `endpoints` SG (HTTPS from the VPC) |
| Route 53 private zone `<workspace host>` | `enable_privatelink`: A alias to the endpoint, so tasks in the VPC reach the normal workspace URL over PrivateLink |

The Databricks service-principal credential is **not** created here. The model-refresh state
machine calls the Jobs API through the EventBridge connection `<prefix>-databricks` (OAuth client
credentials, stack `data.tf`); DevOps sets its client secret out of band from the values WBD
Databricks admins hand over (docs/05).

## Two-phase Unity Catalog role

Databricks requires the role to trust **itself**, and a role can't trust itself before it exists.

| Phase | tfvars | Then |
|---|---|---|
| 1 | `enable_data_platform = true`, `databricks_self_assume_enabled = false` | Apply. Give WBD Databricks `terraform output data_platform` → `uc_role_arn`. WBD creates the storage credential + external locations (`s3://<bucket>/`) |
| 2 | `databricks_self_assume_enabled = true` | Apply again. WBD clicks **Validate configuration** on the storage credential: all checks green |

The trust always requires `sts:ExternalId = databricks_account_id`.

## PrivateLink

Off until WBD gives the endpoint service name for the region (`databricks_privatelink_service_name`)
and registers the endpoint ID (`workspace_endpoint_id` output) in the Databricks account
console. Without it, tasks reach the workspace over HTTPS through NAT; the workspace IP access
list must then allow `nat_public_ips`. Step Functions HTTP tasks always call the public workspace
URL, so the IP access list must also allow AWS Step Functions (or stay open to the WBD-approved
ranges) – confirm with WBD Databricks.

## Inputs

| Name | Type | Default |
|---|---|---|
| `name_prefix` | string | – |
| `databricks_account_id` | string | – |
| `uc_master_role_arn` | string | Databricks UC master role (AWS commercial) |
| `self_assume_enabled` | bool | `false` |
| `bucket_arns`, `kms_key_arns` | list(string) | – |
| `enable_privatelink` | bool | `false` |
| `workspace_host`, `workspace_service_name` | string | – / `null` |
| `vpc_id`, `endpoint_subnet_ids`, `endpoint_security_group_id` | – | – |
| `permissions_boundary_arn` | string | – |

## Outputs

`uc_role_arn`, `uc_external_id`, `workspace_endpoint_id`, `private_zone_id`.

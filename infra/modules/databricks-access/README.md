# databricks-access

Private, least-privilege access between this account and the **WBD-owned** Databricks workspace.

**Status:** implemented in Step 13, v4 (created only when `enable_data_platform = true`).

In v4 Databricks is only the **source catalog**: the WBD export job writes the raw extract into
this account and nothing else. The lakehouse, the training snapshots and the evaluation results
are AWS-side (Glue, SageMaker) and Databricks has no access to them.

## What it creates

| Resource | Notes |
|---|---|
| IAM role `mmm-<env>-databricks-uc` | Unity Catalog **storage credential**, write-only target. Get / Put / Delete only under `write_prefixes` (the stacks pass landing `raw/databricks/`), list only those prefixes, `GetBucketLocation`; optional read-only `read_only_prefixes` (default none); the data keys (s3 + per-BU keys). No lifecycle or bucket-policy permissions. Permission boundary |
| VPC endpoint (Interface) | `enable_privatelink`: the workspace REST/UI endpoint service, in the private-endpoint subnets, `endpoints` SG (HTTPS from the VPC) |
| Route 53 private zone `<workspace host>` | `enable_privatelink`: A alias to the endpoint, so the export Lambda in the VPC reaches the normal workspace URL over PrivateLink |

The Databricks service-principal credential is **not** created here. The export Lambda
(`databricks-export` module) reads it from `mmm/<env>/databricks/export-sp`; DevOps fills the
secret out of band from the values WBD Databricks admins hand over (docs/05).

## Two-phase Unity Catalog role

Databricks requires the role to trust **itself**, and a role can't trust itself before it exists.

| Phase | tfvars | Then |
|---|---|---|
| 1 | `enable_data_platform = true`, `databricks_self_assume_enabled = false` | Apply. Give WBD Databricks `terraform output data_platform` → `uc_role_arn`. WBD creates the storage credential + the external location `s3://<landing>/raw/databricks/` |
| 2 | `databricks_self_assume_enabled = true` | Apply again. WBD clicks **Validate configuration** on the storage credential: all checks green |

The trust always requires `sts:ExternalId = databricks_account_id`.

## PrivateLink

Off until WBD gives the endpoint service name for the region (`databricks_privatelink_service_name`)
and registers the endpoint ID (`workspace_endpoint_id` output) in the Databricks account
console. Without it, the export Lambda reaches the workspace over HTTPS through NAT; the
workspace IP access list must then allow `nat_public_ips`.

## Inputs

| Name | Type | Default |
|---|---|---|
| `name_prefix` | string | – |
| `databricks_account_id` | string | – |
| `uc_master_role_arn` | string | Databricks UC master role (AWS commercial) |
| `self_assume_enabled` | bool | `false` |
| `write_prefixes` | list(object({ bucket_arn, prefix })) | – (at least one; prefix ends in `/`) |
| `kms_key_arns` | list(string) | – |
| `read_only_prefixes` | list(object({ bucket_arn, prefix })) | `[]` |
| `enable_privatelink` | bool | `false` |
| `workspace_host`, `workspace_service_name` | string | – / `null` |
| `vpc_id`, `endpoint_subnet_ids`, `endpoint_security_group_id` | – | – |
| `permissions_boundary_arn` | string | – |

## Outputs

`uc_role_arn`, `uc_external_id`, `workspace_endpoint_id`, `private_zone_id`.

# rds

RDS for PostgreSQL **DB instance** behind **RDS Proxy** – the application database (plans, runs,
allocations, users, audit). v3 architecture (`wbd_Presentation_3.pptx` shows "RDS PostgreSQL");
replaces the v2 `aurora` module.

**Status:** implemented (v3 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_db_instance` `<prefix>-postgres` | Engine `postgres` (`engine_version`, default 16.6), `instance_class`, gp3 storage `allocated_storage` with autoscaling up to `max_allocated_storage`. KMS-encrypted, IAM DB auth on, `rds.force_ssl = 1`, `pgaudit`, logs exported to CloudWatch, PITR `backup_retention_days`, `copy_tags_to_snapshot`, final snapshot, deletion protection. `multi_az` = standby in a second AZ with automatic failover. Performance Insights (KMS, 7 days), Enhanced Monitoring (60 s) |
| Admin secret | `manage_master_user_password = true`: RDS creates and rotates `mmm_admin`'s password in Secrets Manager (KMS `secrets`) |
| `aws_db_proxy` `<prefix>-postgres-proxy` | `require_tls`, `iam_auth = REQUIRED`, idle timeout 30 min, max 90 % of connections. Users: the admin secret + `proxy_user_secret_arns` (`mmm_app`, `mmm_migrator`) |
| Parameter group, subnet group, log groups (`postgresql`, `upgrade`), monitoring + proxy roles | Roles carry the permission boundary |

Clients (ECS tasks, the results-publisher Lambda) connect **only** to `proxy_endpoint` with an IAM
token (`rds-db:connect` on `dbuser:<proxy_resource_id>/<user>`); no client knows a DB password.
Multi-AZ failover keeps the endpoint; the proxy reconnects (about 1–2 minutes).

## Sizing (environment defaults, confirm with WBD)

| Env | Class | Multi-AZ | Storage (GiB) | PITR |
|---|---|---|---|---|
| dev | `db.t4g.medium` | no | 50 → 200 | 7 days |
| staging | `db.r6g.large` | yes | 100 → 500 | 14 days |
| prod | `db.r6g.xlarge` | yes | 200 → 1000 | 35 days |

## Checkov skips (with reason)

| Check | Reason |
|---|---|
| `CKV_AWS_293` | Deletion protection is set per environment (on in prod). |
| `CKV_AWS_157` | Multi-AZ is set per environment (staging, prod); dev is single-AZ to save cost. |
| `CKV2_AWS_60` | `copy_tags_to_snapshot` is set; no read replicas are built. |

## Inputs

`name_prefix`, `subnet_ids` (private-data), `db_security_group_id`, `proxy_security_group_id`,
`engine_version`, `instance_class`, `allocated_storage`, `max_allocated_storage`, `multi_az`,
`db_name` (`mmm`), `master_username` (`mmm_admin`), `deletion_protection`, `backup_retention_days`
(35), `apply_immediately`, `kms_key_arn` (rds), `secrets_kms_key_arn`, `logs_kms_key_arn`,
`log_retention_days`, `pgaudit_log`, `permissions_boundary_arn`, `proxy_user_secret_arns`, `tags`,
`instance_tags` (`{ backup = "true" }`).

## Outputs

`instance_identifier`, `instance_arn`, `endpoint`, `db_name`, `port`, `master_user_secret_arn`,
`proxy_endpoint` (the `DB_HOST`), `proxy_arn`, `proxy_resource_id`, `log_group_name`.

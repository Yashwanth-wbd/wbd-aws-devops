# aurora

Aurora PostgreSQL **Serverless v2** cluster behind **RDS Proxy** – the application database
(runs, scenarios, users, audit). Replaces the v1 `rds` module.

**Status:** implemented (v2 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_rds_cluster` `<prefix>-aurora` | Engine `aurora-postgresql` (`engine_version`, default 16.6), `provisioned` mode with Serverless v2 scaling `min_acu`–`max_acu`. KMS-encrypted storage, IAM DB auth on, `rds.force_ssl = 1`, `pgaudit`, logs exported to CloudWatch, 35-day PITR, `copy_tags_to_snapshot`, deletion protection |
| `aws_rds_cluster_instance` × `instance_count` | `db.serverless`; 1 in dev, 2 (writer + reader in another AZ) in staging/prod. Performance Insights (KMS, 7 days), Enhanced Monitoring |
| Admin secret | `manage_master_user_password = true`: RDS creates and rotates `mmm_admin`'s password in Secrets Manager (KMS `secrets`) |
| `aws_db_proxy` `<prefix>-aurora-proxy` | `require_tls`, `iam_auth = REQUIRED`, idle timeout 30 min, max 90 % of connections. Users: the admin secret + `proxy_user_secret_arns` (`mmm_app`, `mmm_migrator`) |
| Parameter groups, subnet group, log group, monitoring + proxy roles | Roles carry the permission boundary |

Clients (ECS tasks, the results-publisher Lambda) connect **only** to `proxy_endpoint` with an IAM
token (`rds-db:connect` on `dbuser:<proxy_resource_id>/<user>`); no client knows a DB password.

## Sizing

| Env | Instances | ACU |
|---|---|---|
| dev | 1 | 0.5 – 4 |
| staging | 2 | 0.5 – 16 |
| prod | 2 | 1 – 32 |

## Inputs

`name_prefix`, `subnet_ids` (private-data), `db_security_group_id`, `proxy_security_group_id`,
`engine_version`, `min_acu`, `max_acu`, `instance_count`, `db_name` (`mmm`), `master_username`
(`mmm_admin`), `deletion_protection`, `backup_retention_days` (35), `apply_immediately`,
`kms_key_arn` (rds), `secrets_kms_key_arn`, `logs_kms_key_arn`, `log_retention_days`, `pgaudit_log`,
`permissions_boundary_arn`, `proxy_user_secret_arns`, `tags`, `cluster_tags` (`{ backup = "true" }`).

## Outputs

`cluster_identifier`, `cluster_arn`, `writer_endpoint`, `instance_identifiers`, `db_name`, `port`,
`master_user_secret_arn`, `proxy_endpoint` (the `DB_HOST`), `proxy_arn`, `proxy_resource_id`, `log_group_name`.

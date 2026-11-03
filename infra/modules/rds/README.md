# rds

RDS for PostgreSQL behind RDS Proxy. Applications never connect to the instance directly, and
they never use a password.

**Status:** implemented in Step 6.

## Files

| File | Contents |
|---|---|
| `main.tf` | Subnet group, parameter group, log groups, Enhanced Monitoring role, DB instance |
| `proxy.tf` | Proxy IAM role, RDS Proxy, default target group, target |

## DB instance `mmm-<env>-pg`

| Setting | Value |
|---|---|
| Engine | PostgreSQL 16 (minor upgrades automatic, major upgrades only on purpose) |
| Admin password | `manage_master_user_password = true`: RDS creates it in Secrets Manager (encrypted with the `secrets` key) and rotates it every 7 days. Nobody types or sees it. |
| Storage | gp3, autoscaling up to `max_allocated_storage`, encrypted with the `rds` key |
| Network | Private-data subnets, `rds` security group (only RDS Proxy can connect), not publicly accessible |
| TLS | `rds.force_ssl = 1`; CA `rds-ca-rsa2048-g1` |
| Auditing | `pgaudit` loaded (`pgaudit.log = ddl,role`), DDL statements, connections and statements slower than 1 s are logged. Logs go to CloudWatch `/aws/rds/instance/mmm-<env>-pg/postgresql` (KMS-encrypted). |
| Monitoring | Enhanced Monitoring every 60 s; Performance Insights (7 days, KMS) |
| Backups | Point-in-time recovery for `backup_retention_days` (dev 7, prod 35); a final snapshot is taken on delete |
| Per environment | dev: single-AZ, can be deleted. staging: Multi-AZ. prod: Multi-AZ with deletion protection. |

The migration task enables the extension once, with `CREATE EXTENSION pgaudit;` (Step 7).

## RDS Proxy `mmm-<env>-pg-proxy`

- **TLS required** and **IAM authentication required.** A client connects with a 15-minute
  IAM auth token and needs `rds-db:connect` on
  `arn:aws:rds-db:<region>:<account>:dbuser:<proxy_resource_id>/<db_user>`. The ECS task roles
  get this in Step 7, each for its own DB user only.
- The proxy logs in to PostgreSQL with these secrets, which only the proxy role can read:

  | Secret | DB user | Used by |
  |---|---|---|
  | RDS-managed admin secret | `mmm_admin` | Break-glass and first bootstrap only (DevOps through SSO) |
  | `mmm/<env>/rds/proxy` | app user (e.g. `mmm_app`) | API and workers |
  | `mmm/<env>/rds/migrate` | migration user (e.g. `mmm_migrator`, schema owner) | Migrate task |

- The app and migrate secrets are empty when the proxy is created. Until DevOps fills them
  (see the first-time database setup in `infra/environments/dev/README.md`), the proxy target
  shows those users as `AUTH_FAILURE`, which is expected.
- Pool settings: 90 % of `max_connections`, 50 % idle, 120 s borrow timeout.

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | e.g. `mmm-dev` |
| `subnet_ids` | – | Private-data subnets |
| `db_security_group_id` / `proxy_security_group_id` | – | From the network module |
| `engine_version` | `"16"` | Major version |
| `instance_class` | `db.t4g.medium` | |
| `allocated_storage` / `max_allocated_storage` | `50` / `200` | GiB |
| `db_name` / `master_username` | `mmm` / `mmm_admin` | |
| `multi_az` / `deletion_protection` | `true` / `true` | The dev stack sets both to false |
| `backup_retention_days` | `35` | |
| `apply_immediately` | `false` | true in dev |
| `kms_key_arn` / `secrets_kms_key_arn` / `logs_kms_key_arn` | – | From the kms module |
| `log_retention_days` | `90` | |
| `pgaudit_log` | `"ddl,role"` | |
| `permissions_boundary_arn` | – | |
| `proxy_user_secret_arns` | – | App and migration user secrets |

## Outputs

`db_instance_identifier`, `db_instance_arn`, `db_instance_address`, `db_name`, `port`,
`master_user_secret_arn`, `proxy_endpoint` (this is `DB_HOST`), `proxy_arn`, `proxy_resource_id`.

# backup

AWS Backup for the data that cannot be rebuilt from code: the RDS database and the `results` and
`approved-worm` buckets.

**Status:** implemented in Step 10. Restore procedures and RPO/RTO are in
[docs/08-backup-and-dr.md](../../../docs/08-backup-and-dr.md).

## What it creates

| Resource | Name | Notes |
|---|---|---|
| KMS key | `alias/<prefix>-backup` | Separate from the data keys, so a compromised data key does not expose the backups. |
| Vault | `<prefix>-vault` | Recovery points of the stack's region. |
| Vault policy | – | `deny_manual_deletion = true` (staging, prod): nobody may delete a recovery point or shorten its life; only expiry removes it. Off in dev, so dev can be torn down. |
| Vault lock | – | Only if `vault_lock` is set (prod, with WBD approval). See the warning below. |
| Backup role | `<prefix>-backup` | AWS managed backup and restore policies, including S3. Permission boundary attached. |
| Plan | `<prefix>-daily` | `daily` rule at 04:00 UTC, after the RDS backup window. Optional `monthly` rule on the 1st. Optional copy to the DR vault. |
| Selection | `<prefix>-tag-backup` | Every resource tagged `backup = true`. |
| EventBridge rule | `<prefix>-backup-job-failed` | Backup, copy or restore job `FAILED`, `ABORTED` or `EXPIRED`, sent to the alert topic. |
| DR key and vault (`aws.dr`) | `alias/<prefix>-backup-dr`, `<prefix>-vault-dr` | Only with `enable_cross_region_copy = true`. |

## What is backed up, and how

| Data | Protection |
|---|---|
| RDS PostgreSQL | **Native PITR** (7 / 14 / 35 days; restore to any second) **plus** AWS Backup daily snapshots, copied to the DR region in prod |
| S3 `results`, `approved-worm` | Versioning (Step 6) for accidental overwrite or delete. AWS Backup daily for loss of the bucket or the account; Object Lock on `approved-worm` |
| ElastiCache | Native daily snapshot (Step 6). It is a cache and can be rebuilt; it is not in AWS Backup (not supported). |
| SQS | Not backed up: jobs are re-submitted from the API or DB |
| Infrastructure | Terraform code and state (versioned state bucket) |
| Secrets | Secrets Manager. Generated secrets are re-created by Terraform; WBD-issued ones are re-requested |

RDS **continuous** backup through AWS Backup is not used. It would take over the RDS backup
retention that Terraform manages; native PITR gives the same RPO.

## Vault lock warning

`vault_lock` creates a **COMPLIANCE** lock. During `changeable_for_days` (3) it can still be
removed. After that **nobody, not even the root user or AWS Support, can remove it or delete a
recovery point before `min_retention_days`**, and the vault cannot be deleted while it holds
recovery points. Turn it on only in prod, after WBD Security approves the retention values.

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix` | – | |
| `selection_tag` | `backup` | |
| `schedule` | `cron(0 4 * * ? *)` | UTC |
| `daily_retention_days` | `35` | dev 7, staging 14, prod 35 |
| `monthly_retention_days` | `null` | prod 365 |
| `deny_manual_deletion` | `true` | `false` in dev |
| `vault_lock` | `null` | `{ min_retention_days, max_retention_days, changeable_for_days }` |
| `enable_cross_region_copy`, `dr_retention_days` | `false`, `35` | |
| `permissions_boundary_arn` | – | |
| `alert_topic_arn` | – | `module.monitoring.alert_topic_arn` |
| `tags` | `{}` | |

The calling stack passes `aws` and `aws.dr`, the DR region, which must be in `allowed_regions`.

## Outputs

`vault_name`, `vault_arn`, `dr_vault_arn` (`null` without copy), `plan_id`, `backup_role_arn`,
`selection_tag`.

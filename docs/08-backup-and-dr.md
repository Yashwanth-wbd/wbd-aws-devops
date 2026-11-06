# 08 – Backup, restore and disaster recovery

What is protected, how fast it comes back (RPO/RTO), and the exact restore steps. The
infrastructure is in `infra/modules/backup` (Step 10) and `infra/modules/rds`.

## 1. RPO and RTO targets

These are proposed values, to be confirmed by WBD (tracked in `docs/01`).
**RPO** = how much data can be lost. **RTO** = how long until the service is back.

| Failure | Example | RPO | RTO | How |
|---|---|---|---|---|
| Bad data or a bad migration | Wrong rows deleted | ≤ 5 min | 1 h | RDS PITR (section 3) |
| Object overwritten or deleted | Results file overwritten | 0 | 15 min | S3 versioning: restore the previous version (section 4) |
| Bucket or many objects lost | Bucket emptied | 24 h | 2 h | AWS Backup S3 restore (section 4) |
| Bad app release | 5xx after deploy | 0 | 10 min | Circuit breaker, or redeploy the previous image ([09](09-cicd-pipelines.md)) |
| One AZ down | AZ outage | 0 | 1–2 min (automatic) | RDS Multi-AZ standby takes over (staging, prod; RDS Proxy keeps the endpoint); Fargate tasks spread across AZs. Dev is Single-AZ: PITR or wait for the AZ |
| Whole environment lost | Account or stack destroyed | 24 h (DB ≤ 5 min if the region is fine) | 4 h | Rebuild from code (section 5) + restore data |
| Region down (prod) | Regional outage | 24 h | 8 h | Rebuild in `dr_region` from code + DR-vault copies (section 6). Needs WBD approval for cross-region copy. |
| Optimization run lost mid-flight | Step Functions or SageMaker failure | n/a | minutes | User re-runs from the API; run state and inputs are in PostgreSQL and S3 |
| Run requests not dispatched | Dispatcher Lambda failing | 0 (requests stay in SQS 4 days, then the DLQ 14 days) | minutes after the fix | Fix the dispatcher, redrive the DLQ ([runbooks/optimization-run-failed.md](runbooks/optimization-run-failed.md)) |

## 2. What protects what

| Data | Day-to-day | Backup | Off-region |
|---|---|---|---|
| RDS PostgreSQL | Instance `mmm-<env_short>-postgres`; Multi-AZ standby (staging, prod) | Native **PITR** (7 / 14 / 35 days per env) **plus** AWS Backup daily instance snapshots (tag `backup=true`) **plus** prod **pre-migration DB snapshot** in `deploy.yml` | AWS Backup copy (prod, optional) |
| S3 `results`, `approved-worm`, `models` | Versioning; Object Lock on approved-worm | AWS Backup daily (tag `backup=true`) | AWS Backup copy (prod, optional) |
| SageMaker Model Registry | Metadata in AWS; artifacts and `evaluation.json` in `models` bucket | Same as `models` bucket | Same as bucket copy |
| S3 `landing` | Versioning | Re-loadable from source systems | – |
| S3 `training-data`, `lakehouse` (data platform) | Versioning; Object Lock on training-data | AWS Backup daily (tag `backup=true`); lakehouse size / cost to be confirmed by WBD (remove it from `backed_up_buckets` in `backup.tf` to exclude it) | AWS Backup copy (prod, optional) |
| S3 `exports` | Versioning | Not backed up (30-day expiry) | – |
| Terraform state | Versioning | – | Bootstrap bucket replication (prod, optional) |

**Decision (Step 12, proposed to WBD):** the off-region copy of `results`, `approved-worm` and
`models` is the AWS Backup cross-region copy (`enable_cross_region_copy`, prod). That keeps one
mechanism, one DR vault and one approval for all data, at RPO 24 h, which matches the proposed
region RTO of 8 h. S3 cross-region **replication** is available in the `s3-bucket` module but is
not switched on unless WBD asks for a shorter RPO.

Details: `infra/modules/backup/README.md`, `infra/environments/dev/backup.tf`.

## 3. Restore the RDS database to a point in time

PITR always creates a **new instance**. The current instance is untouched until you cut over.
Instance id: `mmm-<env_short>-postgres`. RDS Proxy: `mmm-<env_short>-postgres-proxy`.

```powershell
$env:AWS_PROFILE = "mmm-dev-devops"
$db = "mmm-dev-postgres"
$sg  = (terraform output -json security_group_ids | ConvertFrom-Json).rds

aws rds describe-db-instances --db-instance-identifier $db `
  --query "DBInstances[0].[LatestRestorableTime,DBInstanceClass,MultiAZ,DBParameterGroups[0].DBParameterGroupName]"

# 1. Restore a new instance (time in UTC, before the bad change); same subnets, parameter group, KMS key
$restore = "$db-restore"
aws rds restore-db-instance-to-point-in-time `
  --source-db-instance-identifier $db `
  --target-db-instance-identifier $restore `
  --restore-time 2026-11-03T09:55:00Z `
  --db-subnet-group-name "$db-subnets" `
  --db-parameter-group-name "$db-params" `
  --vpc-security-group-ids $sg `
  --enable-iam-database-authentication `
  --no-publicly-accessible
aws rds wait db-instance-available --db-instance-identifier $restore
```

2. **Check the data.** ECS Exec into the migrate task, or connect from a task in the app subnets
   through the **restored instance endpoint** (not the proxy yet) and compare row counts or the
   affected rows.

3. **Choose:**

   - *Copy back a few rows:* export from the restored instance, import into the live instance via
     the proxy, then delete the restore instance when done.
   - *Replace the whole database:* stop writes (scale `api`/`ui` to 0 or maintenance mode, and set
     `max_concurrent_runs` to `0` so no new run starts; requests still queued after
     `max_queue_wait_minutes` are dropped and planners resubmit), then either:
     - **Repoint RDS Proxy** to the restored instance:
       `aws rds deregister-db-proxy-targets --db-proxy-name "$db-proxy" --db-instance-identifiers $db`, then
       `aws rds register-db-proxy-targets --db-proxy-name "$db-proxy" --db-instance-identifiers $restore`, **or**
     - **Rename/swap instances** (`aws rds modify-db-instance --new-db-instance-identifier`, old one
       to `$db-old`, restored one to `$db`, `--apply-immediately`) so Terraform's identifier stays
       `mmm-<env_short>-postgres` (DevOps + DBA—plan carefully; run `terraform plan` afterwards and
       expect only tag / setting corrections).

     After cutover, check
     `aws rds describe-db-proxy-targets --db-proxy-name "$db-proxy"` shows `AVAILABLE`,
     scale services back, restore `max_concurrent_runs`, run `smoke.sh` against `APP_URL`.

**Restore from an AWS Backup recovery point:** AWS Backup console → Vault
`mmm-<env>-vault` → recovery point → Restore (RDS instance) with the subnet group, parameter group
and `rds` security group above, then follow steps 2–3.

**Prod pre-deploy snapshot:** `deploy.yml` creates `mmm-prd-predeploy-<version>-<run>` before
migrations—useful when the failure is tied to a specific release.

## 4. Restore S3 objects

**One object or a few, overwritten or deleted.** Use versioning; this is the fastest way:

```powershell
$b = "wbd-mmm-dev-results-use1"; $k = "path/to/file.parquet"
aws s3api list-object-versions --bucket $b --prefix $k --query "{v:Versions[].[VersionId,LastModified,IsLatest],d:DeleteMarkers[].[VersionId,IsLatest]}"
# deleted: remove the delete marker
aws s3api delete-object --bucket $b --key $k --version-id <delete-marker-version-id>
# overwritten: copy the good version on top
aws s3api copy-object --bucket $b --key $k --copy-source "$b/${k}?versionId=<good-version-id>"
```

**Many objects or the whole bucket.** Use AWS Backup: Vault → S3 recovery point → Restore, then
choose items or the whole bucket. The target is the same bucket or a new one, with SSE-KMS and
the `alias/mmm-<env>-s3` key. The command-line version is in the dev README ("Validate Step 10").

`approved-worm` objects are under Object Lock, so they cannot be deleted or overwritten in the
first place. A restore is only needed if the bucket itself is lost.

## 5. Rebuild a whole environment from code

1. Bootstrap state (Step 1), if the state bucket is gone.
2. Create network, KMS and security groups, then the RDS subnet / parameter groups
   (`terraform apply -target=module.rds.aws_db_subnet_group.this -target=module.rds.aws_db_parameter_group.this`).
3. Restore the database from the latest AWS Backup recovery point **as `mmm-<env_short>-postgres`**,
   using that subnet group, parameter group and the `rds` security group. Adopt into Terraform:
   `terraform import module.rds.aws_db_instance.this mmm-<env_short>-postgres`.
   Without this, the next apply would create an empty database.
4. `terraform apply` the whole stack (Steps 3–10) with the same tfvars. Names are fixed, so
   everything comes back with the same names. Refill WBD-issued secrets ([05](05-secrets-and-config.md)).
5. Restore `results`, `approved-worm` and `models` from AWS Backup (section 4).
6. Deploy the current release (`deploy.yml`), then smoke test.

Run this end to end in staging at least twice a year (Step 15 runbook). Record the measured times
against section 1.

## 6. Region failure (prod, if WBD approves the cross-region copy)

1. In the prod tfvars, set `aws_region` to `dr_region` and use a separate state key. Apply Steps 3–10.
2. Restore the RDS instance and the buckets from the **DR vault** `mmm-prd-vault-dr` (import the instance as in section 5).
3. Point WBD DNS at the new ALB (`terraform output dns_records_for_wbd` or Route 53 alias).
4. Deploy the release. ECR images are copied to the DR region by the promotion job, or rebuilt.

## 7. Regular tests

| Test | How often | Where |
|---|---|---|
| RDS point-in-time restore | Quarterly |
| Multi-AZ failover (`aws rds reboot-db-instance --force-failover`) | Twice a year | staging | staging (dev for the first run, Step 10) |
| S3 object and bucket restore | Quarterly | staging |
| Full environment rebuild | Twice a year | staging |
| Check backup jobs succeed | Weekly (automatic alert on failure) | all |

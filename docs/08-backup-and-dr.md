# 08 – Backup, restore and disaster recovery

What is protected, how fast it comes back (RPO/RTO), and the exact restore steps. The
infrastructure is in `infra/modules/backup` (Step 10).

## 1. RPO and RTO targets

These are proposed values, to be confirmed by WBD (tracked in `docs/01`).
**RPO** = how much data can be lost. **RTO** = how long until the service is back.

| Failure | Example | RPO | RTO | How |
|---|---|---|---|---|
| Bad data or a bad migration | Wrong rows deleted | ≤ 5 min | 1 h | RDS point-in-time restore (section 3) |
| Object overwritten or deleted | Results file overwritten | 0 | 15 min | S3 versioning: restore the previous version (section 4) |
| Bucket or many objects lost | Bucket emptied | 24 h | 2 h | AWS Backup S3 restore (section 4) |
| Bad app release | 5xx after deploy | 0 | 10 min | Circuit breaker, or redeploy the previous image (Step 11) |
| One AZ down | AZ outage | 0 | minutes (automatic) | Multi-AZ RDS and Redis, tasks in 3 AZs (staging, prod) |
| Whole environment lost | Account or stack destroyed | 24 h (DB ≤ 5 min if the region is fine) | 4 h | Rebuild from code (section 5) + restore data |
| Region down (prod) | Regional outage | 24 h | 8 h | Rebuild in `dr_region` from code + DR-vault copies (section 6). Needs WBD approval for cross-region copy. |
| Redis lost | Node failure | n/a (cache) | minutes | Failover (staging, prod), or the app warms the cache again |
| SQS jobs lost | Region failure | in-flight jobs | – | Users re-submit; job state is in the DB |

## 2. What protects what

| Data | Day-to-day | Backup | Off-region |
|---|---|---|---|
| RDS | Multi-AZ (staging, prod) | Native PITR 7 / 14 / 35 days + AWS Backup daily (+ monthly, 1 year, prod) | AWS Backup copy (prod, optional) |
| `results`, `approved-worm` | Versioning, Object Lock (approved) | AWS Backup daily | AWS Backup copy (prod, optional) |
| `landing` | Versioning | Re-loadable from the source systems | – |
| `exports` | Versioning | Not backed up (30-day temporary files) | – |
| Terraform state | Versioning | – | Bootstrap bucket replication (prod, optional) |

**Decision (Step 12, proposed to WBD):** the off-region copy of `results` and `approved-worm` is
the AWS Backup cross-region copy (`enable_cross_region_copy`, prod). That keeps one mechanism, one
DR vault and one approval for all data, at RPO 24 h, which matches the proposed region RTO of 8 h.
S3 cross-region **replication** (RPO in minutes) is ready in the `s3-bucket` module
(`replication` input). It is not switched on, because it needs DR buckets and KMS keys in
us-west-2 plus an Object Lock bucket for `approved-worm`. Turn it on only if WBD asks for a
shorter RPO.

## 3. Restore RDS to a point in time

PITR always creates a **new** instance. The current one is untouched until you cut over.

```powershell
$env:AWS_PROFILE = "mmm-dev-devops"
$id  = "mmm-dev-pg"
$sg  = (terraform output -json security_group_ids | ConvertFrom-Json).rds
aws rds describe-db-instances --db-instance-identifier $id --query "DBInstances[0].LatestRestorableTime"

# 1. Restore next to the current instance (time in UTC, before the bad change)
aws rds restore-db-instance-to-point-in-time `
  --source-db-instance-identifier $id --target-db-instance-identifier "$id-restore" `
  --restore-time 2026-11-03T09:55:00Z `
  --db-subnet-group-name "$id-subnets" --db-parameter-group-name "$id-params" `
  --vpc-security-group-ids $sg --no-publicly-accessible --enable-iam-database-authentication `
  --manage-master-user-password --master-user-secret-kms-key-id "alias/mmm-dev-secrets" `
  --copy-tags-to-snapshot --deletion-protection
# staging / prod: add --multi-az
aws rds wait db-instance-available --db-instance-identifier "$id-restore"     # 15-30 min
```

2. **Check the data.** ECS Exec into the migrate task, or connect from a task in the app subnets,
   to `"$id-restore"` and compare row counts or the affected rows.
3. **Choose:**
   - *Copy back a few rows:* export them from the restored instance, import into the current
     one, then delete the restore (`aws rds delete-db-instance --db-instance-identifier "$id-restore" --skip-final-snapshot`).
     You need to turn deletion protection off first.
   - *Replace the whole database:* scale the services to 0 (or put the API in maintenance), then
     rename the instances:

     ```powershell
     aws rds modify-db-instance --db-instance-identifier $id --new-db-instance-identifier "$id-old" --apply-immediately
     aws rds wait db-instance-available --db-instance-identifier "$id-old"
     aws rds modify-db-instance --db-instance-identifier "$id-restore" --new-db-instance-identifier $id --apply-immediately
     aws rds wait db-instance-available --db-instance-identifier $id

     # Terraform tracks the instance by its resource ID (dbi-...), which still points to "-old".
     terraform state rm module.rds.aws_db_instance.this
     terraform import module.rds.aws_db_instance.this $id
     terraform plan    # proxy target, admin secret ARN, monitoring, tags; review, then apply
     ```

     Check `aws rds describe-db-proxy-targets --db-proxy-name mmm-dev-pg-proxy` returns
     `AVAILABLE`, scale the services back, and delete `"$id-old"` after the incident review.

**Restore from an AWS Backup snapshot** works the same way: AWS Backup console → Vault
`mmm-<env>-vault` → recovery point → Restore. Use the same subnet group, parameter group and
security group. Then do steps 2 and 3.

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
2. Create only what the database restore needs. Terraform also creates their dependencies:
   network, KMS and security groups.

   ```powershell
   terraform apply -target=module.rds.aws_db_subnet_group.this -target=module.rds.aws_db_parameter_group.this
   ```

3. Restore RDS from the latest AWS Backup recovery point **as `mmm-<env>-pg`**, using that subnet
   group, parameter group and the `rds` security group. Then adopt it:
   `terraform import module.rds.aws_db_instance.this mmm-<env>-pg`. Without this, the next apply
   would create an empty database.
4. `terraform apply` the whole stack (Steps 3–10) with the same tfvars. Names are fixed, so
   everything comes back with the same names. Then refill the WBD-issued secrets: Databricks,
   Splunk and third-party (`docs/05`).
5. Restore `results` and `approved-worm` from AWS Backup (section 4).
6. Deploy the current release (Step 11 pipeline), then smoke test.

Run this end to end in staging at least twice a year (Step 15 runbook). Record the measured times
against section 1.

## 6. Region failure (prod, if WBD approves the cross-region copy)

1. In the prod tfvars, set `aws_region` to `dr_region` and use a separate state key. Apply Steps 3–10.
2. Restore RDS and the buckets from the **DR vault** `mmm-prd-vault-dr`.
3. Point WBD DNS (the CloudFront origin) at the new ALB. CloudFront itself is global.
4. Deploy the release. ECR images are copied to the DR region by the promotion job, or rebuilt.

## 7. Regular tests

| Test | How often | Where |
|---|---|---|
| RDS point-in-time restore | Quarterly | staging (dev for the first run, Step 10) |
| S3 object and bucket restore | Quarterly | staging |
| Full environment rebuild | Twice a year | staging |
| Check backup jobs succeed | Weekly (automatic alert on failure) | all |

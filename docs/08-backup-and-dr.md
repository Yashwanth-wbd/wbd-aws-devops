# 08 – Backup, restore and disaster recovery

What is protected, how fast it comes back (RPO/RTO), and the exact restore steps. The
infrastructure is in `infra/modules/backup` (Step 10) and `infra/modules/aurora`.

## 1. RPO and RTO targets

These are proposed values, to be confirmed by WBD (tracked in `docs/01`).
**RPO** = how much data can be lost. **RTO** = how long until the service is back.

| Failure | Example | RPO | RTO | How |
|---|---|---|---|---|
| Bad data or a bad migration | Wrong rows deleted | ≤ 5 min | 1 h | Aurora PITR (section 3) |
| Object overwritten or deleted | Results file overwritten | 0 | 15 min | S3 versioning: restore the previous version (section 4) |
| Bucket or many objects lost | Bucket emptied | 24 h | 2 h | AWS Backup S3 restore (section 4) |
| Bad app release | 5xx after deploy | 0 | 10 min | Circuit breaker, or redeploy the previous image ([09](09-cicd-pipelines.md)) |
| One AZ down | AZ outage | 0 | minutes (automatic) | Aurora reader in another AZ (staging, prod); Fargate tasks spread across AZs |
| Whole environment lost | Account or stack destroyed | 24 h (DB ≤ 5 min if the region is fine) | 4 h | Rebuild from code (section 5) + restore data |
| Region down (prod) | Regional outage | 24 h | 8 h | Rebuild in `dr_region` from code + DR-vault copies (section 6). Needs WBD approval for cross-region copy. |
| Optimization run lost mid-flight | Step Functions or SageMaker failure | n/a | minutes | User re-runs from the API; run state and inputs are in Aurora and S3 |

## 2. What protects what

| Data | Day-to-day | Backup | Off-region |
|---|---|---|---|
| Aurora PostgreSQL | Serverless v2 cluster `mmm-<env_short>-aurora`; writer + reader (staging, prod) | Native **PITR** (7 / 14 / 35 days per env) **plus** AWS Backup daily cluster snapshots (tag `backup=true`) **plus** prod **pre-migration cluster snapshot** in `deploy.yml` | AWS Backup copy (prod, optional) |
| S3 `results`, `approved-worm`, `models` | Versioning; Object Lock on approved-worm | AWS Backup daily (tag `backup=true`) | AWS Backup copy (prod, optional) |
| SageMaker Model Registry | Metadata in AWS; artifacts and `evaluation.json` in `models` bucket | Same as `models` bucket | Same as bucket copy |
| S3 `landing` | Versioning | Re-loadable from source systems | – |
| S3 `training-data` | Object Lock (data platform) | Not in AWS Backup plan (rebuild from lakehouse) | – |
| S3 `exports` | Versioning | Not backed up (30-day expiry) | – |
| Terraform state | Versioning | – | Bootstrap bucket replication (prod, optional) |

**Decision (Step 12, proposed to WBD):** the off-region copy of `results`, `approved-worm` and
`models` is the AWS Backup cross-region copy (`enable_cross_region_copy`, prod). That keeps one
mechanism, one DR vault and one approval for all data, at RPO 24 h, which matches the proposed
region RTO of 8 h. S3 cross-region **replication** is available in the `s3-bucket` module but is
not switched on unless WBD asks for a shorter RPO.

Details: `infra/modules/backup/README.md`, `infra/environments/dev/backup.tf`.

## 3. Restore Aurora to a point in time

PITR always creates a **new cluster**. The current cluster is untouched until you cut over.
Cluster id: `mmm-<env_short>-aurora`. RDS Proxy: `mmm-<env_short>-aurora-proxy`.

```powershell
$env:AWS_PROFILE = "mmm-dev-devops"
$cluster = "mmm-dev-aurora"
$sg  = (terraform output -json security_group_ids | ConvertFrom-Json).rds
$subnet = "$cluster-subnets"

aws rds describe-db-clusters --db-cluster-identifier $cluster `
  --query "DBClusters[0].LatestRestorableTime"

# 1. Restore a new cluster (time in UTC, before the bad change)
$restore = "$cluster-restore"
aws rds restore-db-cluster-to-point-in-time `
  --source-db-cluster-identifier $cluster `
  --db-cluster-identifier $restore `
  --restore-type copy-on-write `
  --restore-time 2026-11-03T09:55:00Z `
  --db-subnet-group-name $subnet `
  --vpc-security-group-ids $sg `
  --no-publicly-accessible
aws rds wait db-cluster-available --db-cluster-identifier $restore

# 2. Add a Serverless v2 instance (required before the cluster accepts connections)
aws rds create-db-cluster-instance `
  --db-cluster-identifier $restore `
  --db-instance-identifier "$restore-01" `
  --db-instance-class db.serverless `
  --engine aurora-postgresql
aws rds wait db-instance-available --db-instance-identifier "$restore-01"
```

3. **Check the data.** ECS Exec into the migrate task, or connect from a task in the app subnets
   through the **restored cluster endpoint** (not the proxy yet) and compare row counts or the
   affected rows.

4. **Choose:**

   - *Copy back a few rows:* export from the restored cluster, import into the live cluster via
     the proxy, then delete the restore cluster when done.
   - *Replace the whole database:* stop writes (scale `api`/`ui` to 0 or maintenance mode), then
     either:
     - **Repoint RDS Proxy** to the restored cluster:
       `aws rds register-db-proxy-targets --db-proxy-name "$cluster-proxy" --db-cluster-identifiers $restore`
       (after deregistering the old target), **or**
     - **Rename/swap clusters** so Terraform's identifier stays `mmm-<env_short>-aurora` and
       import the restored cluster into state (DevOps + DBA—plan carefully).

     After cutover, check
     `aws rds describe-db-proxy-targets --db-proxy-name "$cluster-proxy"` shows `AVAILABLE`,
     scale services back, run `smoke.sh` against `APP_URL`.

**Restore from an AWS Backup recovery point:** AWS Backup console → Vault
`mmm-<env>-vault` → recovery point → Restore (Aurora cluster). Then add a `db.serverless`
instance if the restore job did not create one, and follow steps 3–4.

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
2. Create network, KMS and security groups, then Aurora subnet/parameter groups if needed.
3. Restore Aurora from the latest AWS Backup recovery point **as `mmm-<env_short>-aurora`**
   (or restore beside it and repoint the proxy), using the cluster subnet group and `rds`
   security group. Adopt into Terraform:
   `terraform import module.aurora.aws_rds_cluster.this mmm-<env_short>-aurora` (and instances).
   Without this, the next apply would create an empty database.
4. `terraform apply` the whole stack (Steps 3–10) with the same tfvars. Names are fixed, so
   everything comes back with the same names. Refill WBD-issued secrets ([05](05-secrets-and-config.md)).
5. Restore `results`, `approved-worm` and `models` from AWS Backup (section 4).
6. Deploy the current release (`deploy.yml`), then smoke test.

Run this end to end in staging at least twice a year (Step 15 runbook). Record the measured times
against section 1.

## 6. Region failure (prod, if WBD approves the cross-region copy)

1. In the prod tfvars, set `aws_region` to `dr_region` and use a separate state key. Apply Steps 3–10.
2. Restore Aurora and the buckets from the **DR vault** `mmm-prd-vault-dr`.
3. Point WBD DNS at the new ALB (`terraform output dns_records_for_wbd` or Route 53 alias).
4. Deploy the release. ECR images are copied to the DR region by the promotion job, or rebuilt.

## 7. Regular tests

| Test | How often | Where |
|---|---|---|
| Aurora point-in-time restore | Quarterly | staging (dev for the first run, Step 10) |
| S3 object and bucket restore | Quarterly | staging |
| Full environment rebuild | Twice a year | staging |
| Check backup jobs succeed | Weekly (automatic alert on failure) | all |

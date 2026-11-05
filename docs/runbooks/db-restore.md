# Runbook: database restore

Full procedures with commands: [docs/08 §3](../08-backup-and-dr.md#3-restore-rds-to-a-point-in-time)
(Aurora cluster point in time), [§4](../08-backup-and-dr.md#4-restore-s3-objects) (S3), [§5–6](../08-backup-and-dr.md#5-rebuild-a-whole-environment-from-code) (environment / region).
Targets (docs/08 §1, to be confirmed by WBD): bad data → RPO ≤ 5 min, RTO 1 h; whole environment → RTO 4 h.

Cluster id: `mmm-<env_short>-aurora` (`terraform output aurora.cluster_identifier`).

## Decide

| Situation | Action |
|---|---|
| Some rows deleted or wrong (app bug, bad migration) | Restore **next to** prod to the minute before, copy the rows back (no downtime) |
| Database unusable or most data wrong | Restore next to prod, then **switch** the app to the restored cluster |
| Writer instance or AZ failed | Aurora fails over to the reader in staging/prod (60–120 s). Dev has one instance – restore from PITR if needed |
| Bad change right after a prod release | Pre-deploy cluster snapshot `mmm-prd-predeploy-<version>-<run>` from `deploy.yml` |

## Steps (switch case)

1. SEV1, change ticket, stop writes: scale `api` to 0 (optimizations in flight will fail; cancel
   executions if needed) and tell users (maintenance page if the app has one).
   ```bash
   aws ecs update-service --cluster $P-ecs --service $P-api --desired-count 0
   ```
2. Restore to a new cluster `$P-aurora-restore-<yyyymmddhhmm>` with
   `aws rds restore-db-cluster-to-point-in-time` (docs/08 §3), same subnet group, parameter group,
   security groups and KMS key as the live cluster.
3. Validate on the restored cluster (row counts, the last good scenario) with the DBA / app team.
4. Switch: rename clusters so the RDS Proxy target, alarms, backups and Terraform keep working
   (`$P-aurora` → `$P-aurora-old`, restored → `$P-aurora`), then `terraform plan` in the pipeline
   must show **no unintended replace** of the cluster. Escalate before applying if it does.
5. Scale `api` back (or let autoscaling recover), run the smoke test, watch `aurora-cpu` and API
   errors for 30 minutes.
6. Keep `$P-aurora-old` until the incident review, then delete it with a final snapshot.

## Afterwards

Record the restore (time, RPO achieved, duration) in docs/11 §4.2 format and the incident ticket.

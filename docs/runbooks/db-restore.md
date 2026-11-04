# Runbook: database restore

Full procedures with commands: [docs/08 §3](../08-backup-and-dr.md#3-restore-rds-to-a-point-in-time)
(RDS point in time), [§4](../08-backup-and-dr.md#4-restore-s3-objects) (S3), [§5–6](../08-backup-and-dr.md#5-rebuild-a-whole-environment-from-code) (environment / region).
Targets (docs/08 §1, to be confirmed by WBD): bad data → RPO ≤ 5 min, RTO 1 h; whole environment → RTO 4 h.

## Decide

| Situation | Action |
|---|---|
| Some rows deleted or wrong (app bug, bad migration) | Restore **next to** prod to the minute before, copy the rows back (no downtime) |
| Database unusable or most data wrong | Restore next to prod, then **switch** the app to the restored instance |
| Instance or AZ failed | Nothing: Multi-AZ fails over by itself in 60–120 s. Check the app reconnected |
| Bad change right after a prod release | The pre-deploy snapshot `mmm-prd-predeploy-<version>-<run>` is the restore point |

## Steps (switch case)

1. SEV1, change ticket, stop writes: scale the workers to 0 and tell users (planned maintenance page if the app has one).
   ```bash
   for s in whatif-worker optimizer-worker; do aws ecs update-service --cluster $P-ecs --service $P-$s --desired-count 0; done
   ```
2. Restore to a new instance `$P-pg-restore-<yyyymmddhhmm>` (docs/08 §3), same subnet group,
   parameter group, security group and KMS key; prod: `--multi-az`.
3. Validate on the restored instance (row counts, the last good scenario) with the DBA / app team.
4. Switch: rename (`$P-pg` → `$P-pg-old`, restored → `$P-pg`) so the RDS Proxy target, alarms,
   backups and Terraform keep working, then `terraform plan` in the pipeline must show **no
   replace** of the instance (only tags / minor in-place changes). Escalate before applying if it does.
5. Bring the workers back (autoscaling restores the counts on the next apply, or set them back),
   run the smoke test, watch `rds-cpu` and API errors for 30 minutes.
6. Keep `$P-pg-old` (stopped) until the incident review, then delete it with a final snapshot.

## Afterwards

Record the restore (time, RPO achieved, duration) in docs/11 §4.2 format and the incident ticket.

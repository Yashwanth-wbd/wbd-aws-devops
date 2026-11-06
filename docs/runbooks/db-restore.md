# Runbook: database restore

Full procedures with commands: [docs/08 §3](../08-backup-and-dr.md#3-restore-the-rds-database-to-a-point-in-time)
(RDS instance point in time), [§4](../08-backup-and-dr.md#4-restore-s3-objects) (S3), [§5–6](../08-backup-and-dr.md#5-rebuild-a-whole-environment-from-code) (environment / region).
Targets (docs/08 §1, to be confirmed by WBD): bad data → RPO ≤ 5 min, RTO 1 h; whole environment → RTO 4 h.

Instance id: `mmm-<env_short>-postgres` (`terraform output rds.instance_identifier`), RDS Proxy
`mmm-<env_short>-postgres-proxy`.

## Decide

| Situation | Action |
|---|---|
| Some rows deleted or wrong (app bug, bad migration) | Restore **next to** prod to the minute before, copy the rows back (no downtime) |
| Database unusable or most data wrong | Restore next to prod, then **switch** the app to the restored instance |
| Primary instance or AZ failed | RDS Multi-AZ fails over to the standby in staging/prod (60–120 s, the proxy endpoint stays). Dev is Single-AZ – wait for the AZ or restore from PITR |
| Bad change right after a prod release | Pre-deploy DB snapshot `mmm-prd-predeploy-<version>-<run>` from `deploy.yml` (`aws rds restore-db-instance-from-db-snapshot`) |

## Steps (switch case)

1. SEV1, change ticket, stop writes: scale `api` to 0 and pause new runs with
   `max_concurrent_runs = 0` (optimizations in flight will fail; cancel executions if needed;
   queued requests expire after `max_queue_wait_minutes`), and tell users (maintenance page if the
   app has one).
   ```bash
   aws ecs update-service --cluster $P-ecs --service $P-api --desired-count 0
   aws ssm put-parameter --name /mmm/$E/optimization/max_concurrent_runs --value 0 --overwrite   # PR to tfvars afterwards
   ```
2. Restore to a new instance `$P-postgres-restore-<yyyymmddhhmm>` with
   `aws rds restore-db-instance-to-point-in-time` (docs/08 §3), same subnet group, parameter group,
   security group and KMS key as the live instance, IAM database authentication on.
3. Validate on the restored instance (row counts, the last good scenario) with the DBA / app team.
4. Switch: rename instances so the RDS Proxy target, alarms, backups and Terraform keep working
   (`$P-postgres` → `$P-postgres-old`, restored → `$P-postgres`, `aws rds modify-db-instance
   --new-db-instance-identifier ... --apply-immediately`), re-register the proxy target if it does
   not show `AVAILABLE`, then `terraform plan` in the pipeline must show **no unintended replace** of
   the instance. Escalate before applying if it does.
5. Scale `api` back (or let autoscaling recover), restore `max_concurrent_runs` (apply the tfvars
   value), run the smoke test, watch `rds-cpu`, `rds-connections` and API errors for 30 minutes.
6. Keep `$P-postgres-old` until the incident review, then delete it with a final snapshot.

## Afterwards

Record the restore (time, RPO achieved, duration) in docs/11 §4.2 format and the incident ticket.

# infra/environments/prod – prod account stack

Same code as dev and staging. The `.tf` files, `.terraform.lock.hcl` and `tests/` are copies made
by `scripts/sync-environments.ps1`, and `repo-checks.yml` fails if they drift. **Edit them in dev,
then run the sync.** Only `backend.tf`, `terraform.tfvars` and this README belong to prod.

**Status:** Step 12.

## What is different from staging

All of this comes from `environment = "prod"` and the tfvars, not from different code:

| Item | staging | prod |
|---|---|---|
| Account / prefix | `wbd-mmm-stage`, `mmm-stg` | `wbd-mmm-prod`, `mmm-prd` |
| VPC | `10.40.32.0/19` | `10.40.64.0/19` (placeholder) |
| RDS | db.r6g.large, 14-day PITR | db.r6g.xlarge, **35-day PITR, deletion protection**, storage to 1 TB |
| ALB | – | **deletion protection** |
| ElastiCache snapshots | 1 day | 7 days |
| ECS min–max | api 2–4, what-if 1–4, optimizer 0–5 | api **3–10**, what-if **2–6**, optimizer 0–10 |
| `approved-worm` Object Lock | GOVERNANCE | **COMPLIANCE** (nobody can delete, not even root) |
| Backups | 14 days | **35 days daily + 365 days monthly**; manual deletion denied |
| Vault lock / DR copy | – | `enable_vault_lock` / `enable_cross_region_copy`, both **off until WBD approves in writing** |
| Logs, flow logs, log bucket | 90 days | 365 days |
| PR plans | allowed | **never**: `gha-plan` doesn't trust `pull_request` |
| ECR | rc tags from dev | release tags `vX.Y.Z` copied from staging; no `ecr-read` role (nothing is promoted out of prod) |
| GitHub Environment | EY lead | **WBD approvers, prevent self-review**, change ticket in the tag, RDS snapshot before migrations |
| Okta | `api://mmm-stg` | own app, `api://mmm-prd` |
| Data platform (Step 13, `enable_data_platform`) | `mw1.small` 1–4, rc tags | `mw1.medium` **2–10 workers**, DAGs only from `data-vX.Y.Z` with an rc tag on the same commit (WBD approver); catalog `mmm_prd`; `prod-model-promotion` needs a WBD model approver (prevent self-review) |

Expected first `terraform plan`: **307 to add**. That is staging's 309 minus the `gha-ecr-read`
role and its policy. With the vault lock and the cross-region copy approved, the count grows
(`scripts/mock-plan.ps1 -Environment prod` plans that variant too).

## Build it (first time, after staging is validated)

The steps are the same as in the [staging README](../staging/README.md), with these changes:

1. SSO profile `mmm-prd-devops` (permission set `aws-mmm-prd-devops`). It is used only for the
   bootstrap and the first apply. Daily access is `mmm-prd-readonly`.
2. Bootstrap with `prod.tfvars` (workspace `prod`), then fill `backend.tf` and `state_kms_key_arn`.
3. Replace the placeholders. Prod needs WBD sign-off on the RDS and Redis sizes, the budget and
   the COMPLIANCE retention (2555 days), because COMPLIANCE retention can't be shortened later.
4. First apply: `terraform plan -out=prd.tfplan` (307 to add), then `terraform apply prd.tfplan`.
   The change is under a CAB ticket.
5. Database setup with `enable_db_bootstrap` (as in staging step 5), then set it back to `false`.
   Then run the platform check: `Invoke-Expression (terraform output -raw platform_check_run_command)`.
6. Confirm the alert subscriptions and create the WBD DNS CNAMEs (`dns_records_for_wbd`).
7. GitHub Environment `prod`. The promotion source is staging:

   ```powershell
   # add actual value (repo, team, staging account ID)
   .\scripts\setup-github.ps1 -Repo wbd-org/wbd-mmm-platform -Environment prod -ReviewerTeams wbd-release-approvers `
     -SourceEcrReadRoleArn arn:aws:iam::222222222222:role/mmm-stg-gha-ecr-read `
     -SourceEcrRegistry 222222222222.dkr.ecr.us-east-1.amazonaws.com
   ```

8. **Only after written WBD approval:** set `enable_cross_region_copy = true` and/or
   `enable_vault_lock = true` and merge. The vault lock has a 3-day cool-off; after that it can't
   be removed ([docs/08](../../../docs/08-backup-and-dr.md)).
9. After the go-live checks, set `enable_platform_check_task = false`.

## Validate prod

```powershell
# offline
.\scripts\sync-environments.ps1 -Check
.\scripts\mock-plan.ps1 -Environment prod               # plan + plan_all_features: pass, "Plan: 307 to add"

# account (mmm-prd-readonly is enough for the checks)
aws rds describe-db-instances --db-instance-identifier mmm-prd-pg --query "DBInstances[0].[MultiAZ,BackupRetentionPeriod,DeletionProtection]"   # true, 35, true
aws elbv2 describe-load-balancer-attributes --load-balancer-arn $(aws elbv2 describe-load-balancers --names mmm-prd-alb --query "LoadBalancers[0].LoadBalancerArn" --output text) --query "Attributes[?Key=='deletion_protection.enabled'].Value"   # true
aws s3api get-object-lock-configuration --bucket wbd-mmm-prd-approved-worm-use1 --query "ObjectLockConfiguration.Rule.DefaultRetention"   # COMPLIANCE, 2555
aws backup list-backup-plans --query "BackupPlansList[].BackupPlanName"                                    # mmm-prd-daily (daily + monthly rules)
aws iam get-role --role-name mmm-prd-gha-plan --query "Role.AssumeRolePolicyDocument.Statement[0].Condition"   # no :pull_request subject
```

**Release to prod end to end** (after `v0.1.0-rc1` passed staging and UAT):

```powershell
git tag -a v0.1.0 -m "CHG0000000 MMM 0.1.0" <same commit as v0.1.0-rc1>; git push origin v0.1.0
# deploy waits for a WBD approver; the person who pushed the tag cannot approve (prevent self-review)
gh run watch
gh api repos/wbd-org/wbd-mmm-platform/actions/runs/<run id>/approvals --jq ".[].user.login"   # the approver
aws rds describe-db-snapshots --db-instance-identifier mmm-prd-pg --snapshot-type manual --query "DBSnapshots[-1].DBSnapshotIdentifier"   # mmm-prd-predeploy-v0-1-0-<run>
```

Also check that:
- a tag without a change ticket fails at "Change ticket on the release tag";
- a `vX.Y.Z` tag on a commit without an rc tag fails at "Find source images".

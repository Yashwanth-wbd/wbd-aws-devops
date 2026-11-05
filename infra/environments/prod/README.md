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
| Aurora | 0.5–16 ACU, 14-day PITR | **1–32 ACU**, **35-day PITR, deletion protection** |
| ALB | – | **deletion protection** |
| ECS min–max | api 2–4, ui 2–3 | api **3–10**, ui **2–6** |
| `approved-worm` Object Lock | GOVERNANCE | **COMPLIANCE** (2555 days – cannot shorten later) |
| Backups | 14 days | **35 days daily + 365 days monthly**; manual deletion denied |
| Vault lock / DR copy | – | `enable_vault_lock` / `enable_cross_region_copy`, **off until WBD approves in writing** |
| Logs, flow logs, log bucket | 90 days | 365 days |
| PR plans | allowed | **never**: `gha-plan` doesn't trust `pull_request` |
| ECR | rc tags from dev | release tags `vX.Y.Z` copied from staging; no `ecr-read` role (nothing promoted out of prod) |
| GitHub Environment | EY lead | **WBD approvers, prevent self-review**, change ticket on tag, **Aurora cluster snapshot** before migrations |
| Data platform | rc tags | prod bundles and model promotion with WBD approvers (`prod-model-promotion`, prevent self-review) |

First `terraform plan` on an empty account: `.\scripts\mock-plan.ps1 -Environment prod` (staging
count minus the prod `ecr-read` role; plus vault lock / DR copy when those flags are enabled).

## Build it (first time, after staging is validated)

Same order as the [staging README](../staging/README.md), with these changes:

1. SSO profile `mmm-prd-devops` for bootstrap and first apply; daily access `mmm-prd-readonly`.
2. Bootstrap with `prod.tfvars` (workspace `prod`), then fill `backend.tf` and `state_kms_key_arn`.
3. Replace placeholders. Prod needs WBD sign-off on Aurora ACU limits, budget and COMPLIANCE Object Lock.
4. First apply under a CAB ticket: `terraform plan -out=prd.tfplan`, then `terraform apply prd.tfplan`.
5. Database setup with `enable_db_bootstrap` (as staging), then `enable_db_bootstrap = false`.
   Run `Invoke-Expression (terraform output -raw platform_check_run_command)`.
6. Confirm alert subscriptions and WBD DNS CNAMEs (`dns_records_for_wbd`).
7. GitHub Environment `prod`. Promotion source is staging:

   ```powershell
   # add actual value (repo, team, staging account ID)
   .\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment prod -ReviewerTeams wbd-release-approvers `
     -SourceEcrReadRoleArn arn:aws:iam::222222222222:role/mmm-stg-gha-ecr-read `
     -SourceEcrRegistry 222222222222.dkr.ecr.us-east-1.amazonaws.com
   ```

8. **Only after written WBD approval:** set `enable_cross_region_copy = true` and/or
   `enable_vault_lock = true` and merge ([docs/08](../../../docs/08-backup-and-dr.md)).
9. After go-live checks, set `enable_platform_check_task = false` if WBD wants the check task removed.

## Validate prod

```powershell
# offline
.\scripts\sync-environments.ps1 -Check
.\scripts\mock-plan.ps1 -Environment prod

# account (mmm-prd-readonly is enough for read-only checks)
$cid = (terraform output -json aurora | ConvertFrom-Json).cluster_identifier
aws rds describe-db-clusters --db-cluster-identifier $cid --query "DBClusters[0].[Status,BackupRetentionPeriod,DeletionProtection]"
aws elbv2 describe-load-balancer-attributes --load-balancer-arn $(aws elbv2 describe-load-balancers --names mmm-prd-alb --query "LoadBalancers[0].LoadBalancerArn" --output text) --query "Attributes[?Key=='deletion_protection.enabled'].Value"
aws s3api get-object-lock-configuration --bucket wbd-mmm-prd-approved-worm-use1 --query "ObjectLockConfiguration.Rule.DefaultRetention"
aws backup list-backup-plans --query "BackupPlansList[].BackupPlanName"
aws iam get-role --role-name mmm-prd-gha-plan --query "Role.AssumeRolePolicyDocument.Statement[0].Condition"
```

**Release to prod end to end** (after `v0.1.0-rc1` passed staging and UAT):

```powershell
git tag -a v0.1.0 -m "CHG0000000 MMM 0.1.0" <same commit as v0.1.0-rc1>; git push origin v0.1.0
gh run watch
aws rds describe-db-cluster-snapshots --db-cluster-identifier mmm-prd-aurora --snapshot-type manual --query "DBClusterSnapshots[-1].DBClusterSnapshotIdentifier"   # mmm-prd-predeploy-v0-1-0-<run>
```

Also check that a tag without a change ticket fails at "Change ticket on the release tag", and a
`vX.Y.Z` tag on a commit without an rc tag fails at "Find source images".

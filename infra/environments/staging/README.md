# infra/environments/staging – staging account stack

Same code as dev. The `.tf` files, `.terraform.lock.hcl` and `tests/` are copies made by
`scripts/sync-environments.ps1`, and `repo-checks.yml` fails if they drift. **Edit them in dev,
then run the sync.** Only `backend.tf`, `terraform.tfvars` and this README belong to staging.

**Status:** Step 12.

## What is different from dev

| Item | dev | staging |
|---|---|---|
| Account / prefix | `wbd-mmm-dev`, `mmm-dev` | `wbd-mmm-stage`, `mmm-stg` |
| AZs / NAT | 2 / 1 shared | **3 / one per AZ** |
| VPC | `10.40.0.0/19` | `10.40.32.0/19` (placeholder) |
| Aurora | 1 instance, 0.5–4 ACU, 7-day PITR | **2 instances**, 0.5–16 ACU, 14-day PITR |
| ECS min–max | api 1–2, ui 1–2 | api 2–4, ui 2–3 |
| ECR | builds land here (`sha-*`, 30 kept) | release candidates only (`vX.Y.Z-rcN`), copied from dev |
| OIDC roles | `ecr-push` also trusts `main`; `ecr-read` trusts `staging` | `ecr-push` trusts `staging` only; `ecr-read` trusts `prod` |
| Backups | 7 days, recovery points deletable | **14 days, manual deletion denied** |
| Logs | 30 days | 90 days |
| GitHub Environment | no reviewers | **EY delivery lead approves** |
| Okta SAML | own Okta app (`terraform output okta_app_settings`) | own app for staging |
| Data platform (`enable_data_platform`) | bundles from `main` via `databricks.yml` | same workflow on manual dispatch / tags `v*` only; model promotion needs `staging-model-promotion` |

First `terraform plan` on an empty account: run `.\scripts\mock-plan.ps1 -Environment staging` for
the current resource count (includes the third AZ and backup vault deny policy).

## Build it (first time, in this order)

1. **SSO profile** `mmm-stg-devops` ([docs/02](../../../docs/02-aws-access-sso-cli.md)).
2. **Bootstrap** the state bucket in the staging account (Step 1, `infra/bootstrap`, `staging.tfvars`):

   ```powershell
   $env:AWS_PROFILE = "mmm-stg-devops"; aws sso login --sso-session wbd
   cd infra\bootstrap
   terraform init -reconfigure; terraform workspace new staging
   terraform apply -var-file=staging.tfvars
   terraform output backend_config; terraform output state_kms_key_arn
   ```

   Put the values in `backend.tf` and `state_kms_key_arn` in `terraform.tfvars`.
3. **Replace the placeholders** in `terraform.tfvars` (every `# add actual value`). The ACM
   certificate for `app_domain_name` in the workload region and the staging Okta SAML app must exist first.
4. **First apply from a laptop.** The pipeline roles don't exist yet:

   ```powershell
   cd infra\environments\staging
   terraform init
   terraform plan -out=stg.tfplan
   terraform apply stg.tfplan           # allow 30–40 min (Aurora, ALB)
   ```

5. **Database setup:** set `enable_db_bootstrap = true`, apply, and run
   `Invoke-Expression (terraform output -raw db_bootstrap_run_command)`. Then set it back to
   `false` and apply. Details under "First-time DB setup" in the [dev README](../dev/README.md).
6. **Alert emails:** every address in `alert_emails` confirms the SNS subscription.
7. **DNS:** WBD DNS creates the CNAME from `terraform output dns_records_for_wbd` (or Route 53 alias if configured).
8. **GitHub Environment `staging`** (reviewers, refs, variables). Promotion source is dev:

   ```powershell
   # add actual value (repo, team, dev account ID)
   .\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment staging -ReviewerTeams ey-delivery-leads `
     -SourceEcrReadRoleArn arn:aws:iam::111111111111:role/mmm-dev-gha-ecr-read `
     -SourceEcrRegistry 111111111111.dkr.ecr.us-east-1.amazonaws.com
   ```

From now on staging changes only through the pipeline. A merge to `main` applies dev, then
`apply-staging` waits for the EY lead.

## Validate staging

```powershell
# offline (no AWS)
.\scripts\sync-environments.ps1 -Check
.\scripts\mock-plan.ps1 -Environment staging

# account (mmm-stg-devops)
cd infra\environments\staging
terraform plan -detailed-exitcode                      # exit 0 = no changes after the first apply
aws ec2 describe-nat-gateways --filter Name=tag:Environment,Values=stg --query "NatGateways[].SubnetId" # 3
$cid = (terraform output -json aurora | ConvertFrom-Json).cluster_identifier
aws rds describe-db-clusters --db-cluster-identifier $cid --query "DBClusters[0].[Status,BackupRetentionPeriod,DeletionProtection]"
aws backup get-backup-vault-access-policy --backup-vault-name mmm-stg-vault                                # Deny DeleteRecoveryPoint
Invoke-Expression (terraform output -raw platform_check_run_command)                                       # log ends with PLATFORM CHECK PASSED
```

**Promotion end to end** (after a dev deploy of commit `<c>`):

```powershell
git tag v0.1.0-rc1 <c>; git push origin v0.1.0-rc1
gh run watch                                            # deploy waits for the EY lead -> approve in GitHub
aws ecr describe-images --repository-name mmm/api --image-ids imageTag=v0.1.0-rc1 --query "imageDetails[0].imageDigest"
aws ecr describe-images --repository-name mmm/api --image-ids imageTag=sha-<c7> --query "imageDetails[0].imageDigest" --profile mmm-dev-devops   # must match
```

**Rollback rehearsal** (required before go-live):

```powershell
gh workflow run deploy.yml --ref v0.1.0-rc1 -f environment=staging -f image_tag=v0.0.9-rc1 -f run_migrations=false -f components=all
```

**Restore drill:** follow "Validate Step 10" in the dev README with `mmm-stg-*` names. Record RTO in `docs/08` section 1.

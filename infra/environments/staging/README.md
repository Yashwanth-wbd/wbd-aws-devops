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
| RDS | db.t4g.medium, single-AZ, 7-day PITR | db.r6g.large, **Multi-AZ**, 14-day PITR |
| ElastiCache | 1 node | primary + replica, automatic failover |
| ECS min–max | api 1–2, what-if 1–2, optimizer 0–3 | api 2–4, what-if 1–4, optimizer 0–5 |
| ECR | builds land here (`sha-*`, 30 kept) | release candidates only (`vX.Y.Z-rcN`), copied from dev |
| OIDC roles | `ecr-push` also trusts `main`; `ecr-read` trusts `staging` | `ecr-push` trusts `staging` only; `ecr-read` trusts `prod` |
| Backups | 7 days, recovery points deletable | **14 days, manual deletion denied** |
| Logs | 30 days | 90 days |
| GitHub Environment | no reviewers | **EY delivery lead approves** |
| Okta | `api://mmm-dev` | own app, `api://mmm-stg` |
| Data platform (Step 13, `enable_data_platform`) | MWAA `mw1.small` 1–2 workers, DAGs from `main` | `mw1.small` **1–4**, DAGs from `data-vX.Y.Z-rcN` tags (EY lead approves); catalog `mmm_stg`; model promotion needs `staging-model-promotion` approval |

Expected first `terraform plan`: **309 to add**. That is dev's 292 + 16 for the third AZ (4
subnets, 2 NAT gateways, 2 Elastic IPs, 2 route tables, 2 routes, 4 associations) + 1 vault
policy. The offline check `scripts/mock-plan.ps1 -Environment staging` prints the same number.

## Build it (first time, in this order)

1. **SSO profile** `mmm-stg-devops` ([docs/02](../../../docs/02-aws-access-sso-cli.md)).
2. **Bootstrap** the state bucket in the staging account (Step 1, `infra/bootstrap`, `staging.tfvars`):

   ```powershell
   $env:AWS_PROFILE = "mmm-stg-devops"; aws sso login --sso-session wbd
   cd infra\bootstrap
   terraform init -reconfigure; terraform workspace new staging   # or: workspace select staging
   terraform apply -var-file=staging.tfvars
   terraform output backend_config; terraform output state_kms_key_arn
   ```

   Put the values in `backend.tf` and `state_kms_key_arn` in `terraform.tfvars`.
3. **Replace the placeholders** in `terraform.tfvars` (every `# add actual value`). The ACM
   certificates (ALB in the region, CloudFront in us-east-1) and the staging Okta app must exist first.
4. **First apply from a laptop.** The pipeline roles don't exist yet:

   ```powershell
   cd infra\environments\staging
   terraform init
   terraform plan -out=stg.tfplan       # 309 to add
   terraform apply stg.tfplan           # about 30-40 min (RDS Multi-AZ, ElastiCache, CloudFront)
   ```

5. **Database setup:** set `enable_db_bootstrap = true`, apply, and run
   `Invoke-Expression (terraform output -raw db_bootstrap_run_command)`. Then set it back to
   `false` and apply. Details are under "First-time DB setup" in the
   [dev README](../dev/README.md) (Validate Step 7).
6. **Alert emails:** every address in `alert_emails` confirms the SNS subscription.
7. **DNS:** WBD DNS creates the CNAMEs from `terraform output dns_records_for_wbd`.
8. **GitHub Environment `staging`** (reviewers, refs, variables). The promotion source is dev:

   ```powershell
   # add actual value (repo, team, dev account ID)
   .\scripts\setup-github.ps1 -Repo wbd-org/wbd-mmm-platform -Environment staging -ReviewerTeams ey-delivery-leads `
     -SourceEcrReadRoleArn arn:aws:iam::111111111111:role/mmm-dev-gha-ecr-read `
     -SourceEcrRegistry 111111111111.dkr.ecr.us-east-1.amazonaws.com
   ```

From now on staging changes only through the pipeline. A merge to `main` applies dev, then
`apply-staging` waits for the EY lead.

## Validate staging

```powershell
# offline (no AWS)
.\scripts\sync-environments.ps1 -Check
.\scripts\mock-plan.ps1 -Environment staging           # plan + plan_all_features: pass, "Plan: 309 to add"

# account (mmm-stg-devops)
cd infra\environments\staging
terraform plan -detailed-exitcode                      # exit 0 = no changes after the first apply
aws ec2 describe-nat-gateways --filter Name=tag:Environment,Values=stg --query "NatGateways[].SubnetId" # 3
aws rds describe-db-instances --db-instance-identifier mmm-stg-pg --query "DBInstances[0].[MultiAZ,BackupRetentionPeriod,DeletionProtection]"   # true, 14, false
aws elasticache describe-replication-groups --replication-group-id mmm-stg-redis --query "ReplicationGroups[0].[AutomaticFailover,MultiAZ]"   # enabled, enabled
aws backup get-backup-vault-access-policy --backup-vault-name mmm-stg-vault                                # Deny DeleteRecoveryPoint
Invoke-Expression (terraform output -raw platform_check_run_command)                                       # task log ends with PLATFORM CHECK PASSED
```

**Promotion end to end** (after a dev deploy of commit `<c>`):

```powershell
git tag v0.1.0-rc1 <c>; git push origin v0.1.0-rc1
gh run watch                                            # deploy waits for the EY lead -> approve in GitHub
aws ecr describe-images --repository-name mmm/api --image-ids imageTag=v0.1.0-rc1 --query "imageDetails[0].imageDigest"
# must equal the dev digest of sha-<c7> (same image, no rebuild):
aws ecr describe-images --repository-name mmm/api --image-ids imageTag=sha-<c7> --query "imageDetails[0].imageDigest" --profile mmm-dev-devops
```

**Rollback rehearsal** (required before go-live):

```powershell
gh workflow run deploy.yml --ref v0.1.0-rc1 -f environment=staging -f image_tag=v0.0.9-rc1 -f run_migrations=false
bash scripts/deploy-frontend.sh switch <FRONTEND_KVS_ARN> v0.0.9-rc1
```

**Restore drill:** follow "Validate Step 10" in the dev README, with `mmm-stg-*` names. Record
the measured RTO in `docs/08` section 1.

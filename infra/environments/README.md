# infra/environments – one Terraform stack per AWS account

| Folder | AWS account | State key in that account's bucket | Built in |
|---|---|---|---|
| `dev/` | `wbd-mmm-dev` | `environments/dev/terraform.tfstate` | Steps 3–11 |
| `staging/` | `wbd-mmm-stage` | `environments/staging/terraform.tfstate` | Step 12 (copy of dev) |
| `prod/` | `wbd-mmm-prod` | `environments/prod/terraform.tfstate` | Step 12 (copy of dev) |

The three stacks contain the **same `.tf` files**. Only `backend.tf`, `terraform.tfvars` and
`README.md` differ. Differences between environments (AZ count, sizes, approvals, backups)
come from tfvars values or from `local.is_prod` / `var.environment` checks in the code.

**Change code in `dev/` only**, then copy it to staging and prod:

```powershell
.\scripts\sync-environments.ps1           # copies *.tf (not backend.tf), .terraform.lock.hcl, tests/, ecs/<env>/*.json
.\scripts\sync-environments.ps1 -Check    # what CI runs (repo-checks.yml): exit 1 on any difference
```

The change then reaches each account through the pipeline: dev on merge, then staging and prod
after their approvals.

**Offline plan:** `tests/mock-plan.tftest.hcl` plans the whole stack against a mocked AWS
provider (no credentials, nothing created). It runs twice: once with the tfvars and once with
every optional feature switched on. CI runs it for all three stacks, and locally
`.\scripts\mock-plan.ps1 -Environment dev,staging,prod` does the same.

| Stack | Expected plan on an empty account | With all optional features |
|---|---|---|
| dev | 292 to add | 384 |
| staging | 309 (+3rd AZ, + backup vault deny policy) | 403 |
| prod | 307 (no `ecr-read` role: nothing is promoted out of prod) | 403 |

"All optional features" includes the Step 13 data platform (`enable_data_platform`, the
Unity Catalog self-assume phase and Databricks PrivateLink): +58 resources in each stack.

## Files in each stack

| File | Contents |
|---|---|
| `provider.tf` | Terraform ≥ 1.10, AWS provider `~> 5.60`, `allowed_account_ids`, mandatory `default_tags` |
| `backend.tf` | S3 backend with S3-native locking (values from the bootstrap output) |
| `variables.tf` | All inputs, grouped by step |
| `main.tf` | Locals (names, tags) and the modules of Steps 3–6 (foundation, network, secrets, platform) |
| `ecs.tf` | Step 7: ECS cluster, ALB, task role policies, services and on-demand tasks |
| `edge.tf` | Step 8: CloudFront, WAF, frontend bucket and S3 key grants for CloudFront, seed page |
| `monitoring.tf` | Step 9: alert topic, alarms, event alerts, dashboard, logs data protection, Splunk shipping |
| `backup.tf` | Step 10: AWS Backup vault, daily (+ monthly prod) plan, tag selection, vault lock and DR copy flags |
| `cicd` … | CI/CD workflows live in `.github/workflows` (Step 11) |
| `outputs.tf` | IDs and ARNs used by later steps and by GitHub Environment variables |
| `terraform.tfvars` | Values for this account; placeholders marked `# add actual value` |

## Who runs Terraform

| Phase | How |
|---|---|
| Until the pipeline exists (Steps 3–10, dev) | DevOps engineer, SSO `DevOps` profile, from a laptop |
| After Step 11 | Only GitHub Actions (`terraform.yml`): plan on PR, apply after merge with approvals, nightly drift check |
| Changing the permission boundary | DevOps engineer with SSO (the pipeline role is not allowed to) |

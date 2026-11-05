# infra/environments – one Terraform stack per AWS account

| Folder | AWS account | State key in that account's bucket | Built in |
|---|---|---|---|
| `dev/` | `wbd-mmm-dev` | `environments/dev/terraform.tfstate` | Steps 3–11 |
| `staging/` | `wbd-mmm-stage` | `environments/staging/terraform.tfstate` | Step 12 (copy of dev) |
| `prod/` | `wbd-mmm-prod` | `environments/prod/terraform.tfstate` | Step 12 (copy of dev) |

The three stacks contain the **same `.tf` files**. Only `backend.tf`, `terraform.tfvars` and
`README.md` differ. Differences between environments (AZ count, Aurora ACU, ECS counts, approvals,
backups) come from tfvars values or from `local.is_prod` / `var.environment` checks in the code.

**Change code in `dev/` only**, then copy it to staging and prod:

```powershell
.\scripts\sync-environments.ps1           # copies *.tf (not backend.tf), .terraform.lock.hcl, tests/, ecs/<env>/*.json
.\scripts\sync-environments.ps1 -Check    # what CI runs (repo-checks.yml): exit 1 on any difference
```

The change then reaches each account through the pipeline: dev on merge, then staging and prod
after their approvals.

**Offline plan:** `tests/mock-plan.tftest.hcl` plans the whole stack against a mocked AWS provider.
CI runs it for all three stacks; locally `.\scripts\mock-plan.ps1 -Environment dev,staging,prod`.

Resource counts on an empty account depend on optional flags – use the script output rather than
fixed numbers. With every optional feature on (`enable_data_platform`, `enable_genai`, …) the plan
is larger than the baseline Release 1 stack.

## Files in each stack

| File | Contents |
|---|---|
| `provider.tf` | Terraform ≥ 1.10, AWS provider `~> 5.60`, `allowed_account_ids`, mandatory `default_tags` |
| `backend.tf` | S3 backend with S3-native locking (values from the bootstrap output) |
| `variables.tf` | All inputs, grouped by step |
| `main.tf` | Locals and Steps 3–6 (foundation, network, secrets, ECR, buckets, Aurora) |
| `ecs.tf` | Step 7: ECS cluster, services `api` / `ui`, migrate and platform-check tasks |
| `optimization.tf` | Step 7b: optimization state machine, SageMaker Processing role, publisher Lambda, image SSM params |
| `frontdoor.tf` | Step 8: Cognito, ALB, regional WAF, optional Route 53 alias |
| `monitoring.tf` | Step 9: alert topic, alarms, event alerts, dashboard, Splunk shipping |
| `backup.tf` | Step 10: AWS Backup vault, plan, tag selection |
| `data.tf` | Step 13: model refresh state machine, Databricks access (when `enable_data_platform`) |
| `genai.tf` | Step 14: guardrails + LLM gateway (when `enable_genai`) |
| `outputs.tf` | IDs and ARNs for GitHub Environment variables and validation |
| `terraform.tfvars` | Values for this account; placeholders marked `# add actual value` |

## Who runs Terraform

| Phase | How |
|---|---|
| Until the pipeline exists (Steps 3–10, dev) | DevOps engineer, SSO `DevOps` profile, from a laptop |
| After Step 11 | GitHub Actions (`terraform.yml`): plan on PR, apply after merge, nightly drift |
| Changing the permission boundary | DevOps engineer with SSO (the pipeline role is not allowed to) |

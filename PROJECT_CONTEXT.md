# WBD MMM DevOps – Project Context and Continuation Guide

This file is the memory of the project. Chat sessions are lost when the VDI closes, so everything
needed to continue is written here. **Attach this file (plus `devops_plan_1.txt`) to a new chat to
resume.**

Last updated: 4 Nov 2026 (after Steps 0–15 were implemented, reviewed and pushed).

---

## 0. How to resume in a new chat

Paste this to the AI agent, with this file and `devops_plan_1.txt` attached:

> I'm continuing the WBD MMM DevOps project. Read `PROJECT_CONTEXT.md` in the project root first:
> it lists what is done, the decisions taken, the open gaps and the next steps. The project is at
> `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`
> and on GitHub at https://github.com/Yashwanth-wbd/wbd-aws-devops. Follow the rules in section 3.
> Today I want to: <say what – e.g. "fill the real dev values I have", "fix the pipeline defects">.

If the tools are missing after a VDI reset, ask the agent to run section 3.1 first.

---

## 1. Project snapshot

| Item | Value |
|---|---|
| What | DevOps for the WBD Media-Mix-Modeling (MMM) platform on **Amazon ECS Fargate**: Terraform, ECS task definitions, GitHub Actions CI/CD, scripts, runbooks. App code belongs to the dev teams (only the sample `apps/genai-gateway` is ours). |
| Project folder (source of truth) | `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1` (note the spelling *implmenetation*) |
| GitHub repo | https://github.com/Yashwanth-wbd/wbd-aws-devops – branch `main`, latest commit `211f89a` (Steps 14–15). GitHub = project folder: 297 files, nothing uncommitted (except this file until it is pushed). |
| GitHub login | `gh` CLI logged in as `Yashwanth-wbd` (keyring). After a VDI reset run `gh auth login --web --scopes repo,workflow` again. |
| Requirement documents (in `...\Desktop\wbd_devops\`) | `devops_plan_1.txt` (the step-by-step prompt, Steps 0–15), `wbd_mmm_ecs_final.docx` (client design doc, 15 stages), `aws_resource_list.xlsx` (142 resources per env, sheets dev/staging/prod) |
| AWS accounts | Not provided yet: `wbd-mmm-dev`, `wbd-mmm-stage`, `wbd-mmm-prod` (placeholders `111111111111`, `222222222222`, `333333333333`) |
| Status | **All 16 steps (0–15) implemented with placeholder values and validated offline.** Nothing has been applied to AWS. Real validation is waiting for client values, accounts and the app code. |

---

## 2. Decisions taken (keep these unless the client says otherwise)

| Topic | Decision | Why / where documented |
|---|---|---|
| Container registry | **One ECR per environment**; CI pushes to dev ECR, promotion copies the same digest to staging (`vX.Y.Z-rcN`) and prod (`vX.Y.Z`) with `skopeo` | Matches `aws_resource_list.xlsx` steps 48–51. The docx proposed one shared ECR in a Shared account – conflict noted. `README.md` §3, `docs/09` |
| Shared/tooling account | **Not built** (no `wbd-mmm-shared` stack) | GitHub-hosted runners make it unnecessary. **Needs confirmation with WBD** – the docx puts a VPC/NAT/runners/artifacts there |
| CI runners | GitHub-hosted (`ubuntu-latest`) | docx recommends GitHub-hosted; `docs/00` |
| Repository layout | Single repo (infra + pipelines + ecs + data + docs) | Plan §5 allows monorepo |
| Account security baseline | CloudTrail, GuardDuty, Security Hub, Config, SCPs, account S3 BPA, EBS encryption, Access Analyzer, Macie: **owned by WBD, only verified** | `docs/01` |
| Terraform state lock | S3 native lock file (`use_lockfile = true`, Terraform ≥ 1.10); DynamoDB table optional in bootstrap | `infra/bootstrap/README.md` |
| DR for S3 | AWS Backup cross-region copy (RPO 24 h) instead of S3 replication; module supports CRR if WBD wants RPO in minutes | `docs/08`, `docs/01` |
| App DNS | Route 53 records created by WBD DNS; Terraform outputs `dns_records_for_wbd` | `docs/01` |
| Splunk token | Stored in Secrets Manager `mmm/<env>/splunk/hec` (not a Terraform variable) | `docs/05` |
| Cache engine | ElastiCache **Valkey** (Redis-compatible) | docx alternative |
| Authorization | App RBAC + PostgreSQL row-level security per BU (no OPA) | `docs/06` |
| Release 2 (GenAI) | Built but **off**: `enable_genai = false` + GitHub variable `GENAI_ENABLED` | `docs/12` |
| Data platform | MWAA + EventBridge + Lambda + Databricks, **off**: `enable_data_platform = false` | `docs/10` |
| Placeholders | Every placeholder has `# add actual value` on the line above | `README.md` §6 |
| Naming / tags | `mmm-<env>-<component>`, env = `dev`/`stg`/`prd`; tags Application, Environment, Owner, CostCenter, BusinessUnit, DataClassification, ManagedBy, Component | `README.md` §6 |

---

## 3. Working rules and local environment

**Rules for any change**
1. DevOps only – never write api/worker/frontend app code.
2. No secrets in Git, images or Terraform variables.
3. Terraform is applied by GitHub Actions through OIDC. Exceptions: the one-time state bootstrap and the **first apply** of each account (the pipeline roles don't exist yet) – run from a laptop with SSO.
4. Edit only `infra/environments/dev/*.tf` and `ecs/dev/*.json`, then run `.\scripts\sync-environments.ps1` to copy to staging/prod (CI fails if they differ). `terraform.tfvars`, `backend.tf` and `README.md` are per environment and edited individually.
5. Every placeholder gets `# add actual value` on the line above.
6. Do one step at a time and validate before moving on.

### 3.1 Tools (no admin rights; installed under `C:\Users\yn\tools`)

Reinstall after a VDI reset: `powershell -ExecutionPolicy Bypass -File .\scripts\install-prereqs.ps1`
(uv and actionlint were added by hand last time: `pip install uv`; actionlint binary into `C:\Users\yn\tools\bin`).

| Tool | Version used |
|---|---|
| Terraform | 1.17.1 |
| AWS CLI | 2.39.3 |
| Git | 2.56 |
| GitHub CLI | 2.103.3 |
| jq / tflint / Trivy | 1.8.2 / 0.65.0 / 0.76.1 |
| Node / Python / uv | 22.23 / 3.12 / 0.13.7 |
| actionlint / Checkov | 1.7.12 / latest (run as `python.exe <tools>\python\Scripts\checkov`) |
| Docker | **not installed** (needs admin; only for local image builds – CI builds images) |

PATH line for every new PowerShell window:

```powershell
$t="$env:USERPROFILE\tools"; $env:Path = "$t\bin;$t\git\cmd;$t\git\bin;$t\awscli\Amazon\AWSCLIV2;$t\gh\bin;$t\node;$t\python;$t\python\Scripts;" + $env:Path
```

### 3.2 Fast local copy (the network share is slow for Terraform/git)

```powershell
# share -> local working copy (robocopy exit codes 0-3 = success)
robocopy "\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1" C:\work\wbd /MIR /XD .terraform .venv
```

Git on the share needs a safe-directory exception:

```powershell
git config --global --add safe.directory '%(prefix)///USE_EIS_NTPCFS1.tw.tweis.net/WMAD_Profiles/yn/Desktop/wbd_devops/wbd_devops_implmenetation_1'
```

Last push was done from `C:\work\wbd` (same `.git`), then the share was aligned with
`git fetch origin; git reset origin/main` (keeps the files, moves the branch).

### 3.3 Offline validation commands (all passed on 4 Nov 2026)

```powershell
cd infra; terraform fmt -check -recursive; cd ..
.\scripts\sync-environments.ps1 -Check                 # staging/prod = dev
.\scripts\validate-modules.ps1                          # each module validates
.\scripts\mock-plan.ps1 -Environment dev,staging,prod   # terraform test with mocked AWS
tflint --recursive --config "$PWD\.tflint.hcl"
checkov -d infra --framework terraform --quiet --compact --skip-path .terraform
actionlint
.\scripts\secret-scan.ps1
cd apps\genai-gateway; uv run ruff check .; uv run mypy .; uv run pytest --cov   # 17 tests, 100 %
```

Expected mock-plan results (resources to add):

| Env | Default | All optional features on |
|---|---|---|
| dev | 292 | 431 |
| staging | 309 | 450 |
| prod | 309 | 452 (break-glass alert is prod only) |

Checkov over `infra`: 1,333 passed, 0 failed. tflint, actionlint, secret scan: clean.

---

## 4. What is built (status per step of `devops_plan_1.txt`)

| Step | Content | Status |
|---|---|---|
| 0 | Tools, access guides, project skeleton (`docs/00`, `docs/02`) | Done |
| 1 | `infra/bootstrap`: state bucket (versioned, KMS, TLS-only), KMS key, optional DynamoDB lock; `dev/staging/prod.tfvars` | Done – apply pending accounts |
| 2 | 23 modules in `infra/modules` (pinned `aws ~> 5.60`/`5.80`, `terraform >= 1.6`) | Done |
| 3 | KMS per purpose, permission boundary (on all 14 IAM roles), GitHub OIDC + roles `gha-plan/apply/deploy/ecr-push/ecr-read`, budgets 50/80/100 % + anomaly detection | Done |
| 4 | VPC /19, public/app/data/endpoint subnets, 2 AZ dev / 3 AZ stg-prd, NAT 1 vs per-AZ, gateway + interface endpoints, security groups, flow logs, optional Transit Gateway + Resolver | Done |
| 5 | Secrets Manager containers + SSM parameters, generated Redis token and origin secret, RDS-managed master password | Done |
| 6 | ECR (immutable, enhanced scan, lifecycle), S3 buckets (landing, results, approved-worm Object Lock, exports 30 d, frontend, logs, mwaa, data-quality), RDS PostgreSQL + Proxy (IAM auth, TLS, pgaudit), Valkey, SQS FIFO + DLQ | Done |
| 7 | ECS cluster (Container Insights enhanced, Service Connect), ALB (CloudFront prefix list only, origin-secret check), services api / whatif-worker / optimizer-worker (0→N) / migrate task, autoscaling, circuit breaker, ECS Exec, optional Application Signals sidecar | Done |
| 8 | WAF (managed rules, rate limit, logging), CloudFront (OAC, `/api/*` → ALB, security headers, KVS release switch), ACM inputs; Okta wiring via SSM | Done (Route 53 by WBD) |
| 9 | SNS, alarms (5xx, SQS age, DLQ, RDS CPU, what-if latency, cert expiry, deploy rollback, GuardDuty), dashboard, Firehose → Splunk, log data protection | Done |
| 10 | AWS Backup vault/plan (tag `backup=true`), vault lock (prod), cross-region copy option, RDS PITR 7/14/35 days | Done |
| 11 | Workflows: `api-ci`, `optimizer-ci`, `genai-ci` (via `_python-service-ci`), `frontend-ci`, `terraform` (+`_terraform-apply`), `deploy`, `data`, `model-governance`, `repo-checks`; scripts `smoke.sh`, `run-migration.sh`, `promote-images.sh`, `trigger-ondemand.sh`, `ecs-deploy.sh`, `deploy-frontend.sh`, `setup-github.ps1` | Done |
| 12 | Staging and prod stacks = same code, own `backend.tf` + `terraform.tfvars` | Done |
| 13 | MWAA, data trigger (S3/EventBridge/Lambda, idempotent), Databricks access (Unity Catalog role, PrivateLink), per-BU KMS keys, `data/` DAG + manifest + quality suite, model governance | Done (behind `enable_data_platform`) – real validation deferred by the user |
| Gate | Release 1 readiness pack `docs/11` | Ready – sign-offs open |
| 14 | Bedrock module (guardrail, PrivateLink endpoint, invocation logging, alarms, dashboard, budget), `genai.tf` service on Service Connect, `apps/genai-gateway`, `genai-ci`, `GENAI_ENABLED` in deploy, Dependabot | Done (behind `enable_genai`) |
| 15 | `docs/13-operations-and-handover.md`, 13 runbooks in `docs/runbooks/`, break-glass sign-in alert (prod) | Done – KT sessions/sign-offs at handover |

Repository map: `infra/` (bootstrap, modules, environments), `ecs/<env>/` (task definition overlays),
`.github/workflows/`, `scripts/`, `data/`, `apps/genai-gateway/`, `docs/` (00–13 + runbooks).
Each env folder has a `README.md` with the per-step "Validate" commands.

---

## 5. Open issues and gaps (from the full reviews on 4 Nov 2026)

### 5.1 Code defects – fix first (small)

| # | Problem | Where | Fix |
|---|---|---|---|
| D1 | Trivy setup fails in every CI run (`trivy-action@v0.33.1` without `version:`; download of Trivy 0.65.0 fails, curl exit 6). Seen on GitHub on all 3 commits. | `repo-checks.yml:19`, `_python-service-ci.yml:58,87`, `frontend-ci.yml:77` | Add `version: v0.76.1` (or newer) to each trivy-action step, or upgrade the action |
| D2 | Nightly drift job fails when `TF_PLAN_ROLE_ARN_<ENV>` is not set (no skip like the PR plan job). Seen in the scheduled run. | `terraform.yml:174-193` | Copy the "Role configured?" skip step from the `plan` job |
| D3 | Promotion uses `skopeo` but the workflow never installs it (usually on Ubuntu runners, not guaranteed after the Ubuntu 26 switch) | `deploy.yml` promote steps, `scripts/promote-images.sh` | Add `sudo apt-get install -y skopeo` (or check) before promotion |
| D4 | **Terraform still points at a placeholder GitHub repo**: `github_org = "wbd-org"`, `github_repo = "wbd-mmm-platform"`; real repo is `Yashwanth-wbd/wbd-aws-devops` (or the final WBD repo). OIDC trust would reject the pipelines. | `infra/environments/*/terraform.tfvars:23-26`, `scripts/setup-github.ps1:34` default | Set to the real org/repo before the first apply |

### 5.2 Gaps vs `devops_plan_1.txt`

- No `.github/CODEOWNERS` (needs WBD team names; can be added with placeholders).
- No automated DAST (OWASP ZAP baseline against staging before prod) – only a manual item R3 in `docs/11`.
- `MLFLOW_TRACKING_URI` not exported as a GitHub variable (it is the constant `databricks` on the worker tasks; no workflow needs it yet).

### 5.3 Gaps vs the design doc (`wbd_mmm_ecs_final.docx`) and resource list

| Item | Status | Priority |
|---|---|---|
| SBOM (Syft) in CI | missing | should-have |
| Image signing (cosign) | missing | if WBD mandates |
| Dev cost controls (overnight scale-down, stop RDS out of hours) | only optimizer scales to 0 | should-have |
| What-if pool scheduled scaling (business hours) | missing | should-have |
| Fargate Spot for dev workers | module flag exists, not enabled | should-have |
| Performance tests (k6/Locust) | missing | should-have (Stage 13) |
| Post-deploy integration tests | only `/api/health` smoke test | should-have |
| More dashboards (API, optimizer, DB, pipelines, model, cost) | one platform + one GenAI dashboard | should-have |
| More alarms (99.5 % availability, optimization runtime, RDS connections > 80 %, failed Airflow run / stale data, model drift) | partial; several need app metrics | should-have |
| Application Signals | built, `enable_application_signals = false` everywhere | enable when apps exist |
| CloudWatch Synthetics canary (staging/prod, optional) | missing | optional |
| Business-continuity one-page procedure | missing | should-have (doc) |
| Shared account (`wbd-mmm-shared`) | not built – **decision to confirm with WBD** | decision |
| Access Analyzer, Macie, CloudFront VPC origin, EventBridge Scheduler, Chatbot/Teams | not built (optional / WBD-owned) | optional |

### 5.4 Not in this repo but needed before a real deployment works

- App code: `apps/api`, `apps/optimizer-worker`, `apps/frontend` (dev teams). Until then `api-ci`, `optimizer-ci`, `frontend-ci` fail and there is nothing to deploy. Their start/migration commands go into `ecs/<env>/*.json`.
- Real values (section 6), issued ACM certificates, WBD DNS records.
- Open Dependabot PR: https://github.com/Yashwanth-wbd/wbd-aws-devops/pull/1 (action version bumps; its CI fails for the reasons above).

---

## 6. Values to collect from the client and where they go

Full list with owners: `docs/01-client-inputs-tracker.md`. Find every placeholder:
`git grep -n -A1 "add actual value"`. Edit each environment's `terraform.tfvars` separately.

### 6.1 AWS accounts and region
| Value | Where |
|---|---|
| Account IDs dev / staging / prod | `infra/bootstrap/<env>.tfvars` `aws_account_id`; `infra/environments/<env>/terraform.tfvars` `aws_account_id` |
| Region (+ allowed regions, DR region) | `aws_region`, `allowed_regions`, `dr_region` (tfvars), `region` in `backend.tf` |
| Cost center | `cost_center` (bootstrap + env tfvars) |
| SSO access (permission sets: ReadOnly/Developer/DevOps/Security/BreakGlass) | `docs/02`; break-glass permission set name: if it isn't `BreakGlass`, pass `breakglass_permission_set` to `module "monitoring"` in `infra/environments/dev/monitoring.tf` (module default today) |
| Existing GitHub OIDC provider in the account? | if yes: `create_github_oidc_provider = false` + `existing_github_oidc_provider_arn` |
| Existing cost anomaly monitor / Bedrock invocation logging / CloudWatch Logs data-protection policy? | if yes: `enable_cost_anomaly_detection`, `enable_bedrock_invocation_logging`, `enable_log_data_protection` = `false` |

### 6.2 Network
| Value | Where |
|---|---|
| VPC CIDR per env (/19, no overlap with WBD) | `vpc_cidr` (dev placeholder `10.40.0.0/19`) |
| AZ IDs (2 dev, 3 stg/prod) | `availability_zone_ids` |
| Transit Gateway ID + routes (optional) | `transit_gateway_id`, `transit_gateway_routes`, enable flag |
| DNS forwarding domains + WBD resolver IPs (optional) | `resolver_forward_domains`, `resolver_target_ips`, enable flag |
| Central egress instead of NAT? | `enable_nat_gateway` |

### 6.3 DNS, certificates, edge
| Value | Where |
|---|---|
| App names (`mmm-dev`, `mmm-stg`, `mmm` .domain) | `cloudfront_aliases` |
| ALB origin name (`origin-mmm-dev...`) | `alb_origin_domain_name` |
| ACM cert ARN in us-east-1 for CloudFront (must be **ISSUED**) | `cloudfront_certificate_arn` |
| ACM cert ARN in the project region for the ALB (ISSUED) | `alb_certificate_arn` |
| Geo restriction (optional) | `geo_allow_countries` |
| After apply: give WBD DNS the CNAMEs from `terraform output dns_records_for_wbd` | – |

### 6.4 Okta (one app per environment)
`okta_issuer`, `okta_spa_client_id`, `okta_audience` (tfvars → SSM `/mmm/<env>/okta/*`). Details: `docs/04`.

### 6.5 GitHub
| Value | Where |
|---|---|
| Final org/repo (now `Yashwanth-wbd/wbd-aws-devops`) | `github_org`, `github_repo` (tfvars), `-Repo` of `setup-github.ps1` |
| Reviewer teams/users: staging (EY delivery lead), prod (WBD approvers + CAB), model approvers | `setup-github.ps1 -ReviewerTeams/-ReviewerUsers/-ModelApproverTeams` |
| CODEOWNERS teams (DevOps for `infra/**`, `.github/**`, `ecs/**`; app teams for `apps/**`) | `.github/CODEOWNERS` (to create) |
| Change-ticket format for prod tags | `deploy.yml:165` (`CHANGE_TICKET_PATTERN` variable optional) |

### 6.6 Data platform (Step 13)
`databricks_host`, `databricks_sql_http_path`, `databricks_account_id`, `databricks_privatelink_service_name`,
`databricks_eval_client_id`, `databricks_promote_client_id`, business units, `third_party_vendors`,
`data/model-thresholds.yaml` (Week-1 acceptance thresholds), then `enable_data_platform = true`.
Unity Catalog role is two-phase: apply → register in Databricks → `databricks_self_assume_enabled = true` → apply.

### 6.7 Monitoring, budgets, backup
`alert_emails`, `budget_alert_emails`, `monthly_budget_usd`, `splunk_hec_endpoint` (+ `enable_splunk_shipping = true`),
`approved_worm_lock_mode` (GOVERNANCE vs COMPLIANCE – **cannot be undone**), `approved_worm_retention_days`,
prod `enable_vault_lock` / `enable_cross_region_copy` (WBD approval; vault lock is irreversible), sizing
(`rds_instance_class`, `redis_node_type`, task counts).

### 6.8 GenAI (Release 2, after the Release 1 gate)
`genai_approved_model_ids`, `genai_token_quotas`, `genai_monthly_budget_usd` (200/500/2000), `genai_budget_service_names`,
`genai_grounding_threshold`, `genai_relevance_threshold`, `genai_guardrail_version_label`, then `enable_genai = true`
and GitHub variable `GENAI_ENABLED=true`. Enable the model in the Bedrock console per account.

### 6.9 Images and pipelines
GenAI base image (`apps/genai-gateway/Dockerfile` `PYTHON_IMAGE`, WBD-approved registry), Semgrep rule packs
(`repo-checks.yml:35`), frontend build folder (`frontend-ci.yml:91`), app start/migration commands (`ecs/<env>/*.json`).

---

## 7. Secrets (never in Git – filled in AWS after the first apply)

| Secret (`mmm/<env>/...`) | Filled by | When |
|---|---|---|
| `redis/token`, `edge/origin-verify` | Terraform (`random_password`) | automatic |
| RDS master password | RDS-managed, auto-rotated | automatic |
| `rds/migrate`, `rds/proxy`, `api/db` | DB bootstrap task (`enable_db_bootstrap = true`, apply, run `terraform output -raw db_bootstrap_run_command`, then set back to `false`) | **before the first migration/deploy** |
| `databricks/sp` | WBD Databricks admins → then `databricks_token_available = true` | Step 13 |
| `airflow/connections/databricks_default` | DevOps (JSON connection) | Step 13 |
| `splunk/hec` (`{"hec_token":"..."}`) | WBD Splunk team | before `enable_splunk_shipping = true` |
| `thirdparty/<vendor>` | WBD data owners | when the feed is used |

GitHub needs **no secrets** (OIDC). Details: `docs/05`.

---

## 8. GitHub configuration (Step 11)

- Environments: `dev` (no reviewers, `main` only), `staging` (EY delivery lead; `main`, `v*`, `data-v*`),
  `prod` (WBD approvers, prevent self-review; `main`, `v*`, `data-v*`), optional `<env>-model-promotion`.
- Branch protection on `main`: PR + 1–2 reviews (CODEOWNERS), checks green, no force push, linear history.
- **Environment variables** (from `terraform output github_environment_variables`, set by `setup-github.ps1`):
  `AWS_REGION, AWS_DEPLOY_ROLE_ARN, ECR_PUSH_ROLE_ARN, TF_PLAN_ROLE_ARN, TF_APPLY_ROLE_ARN, ECR_REGISTRY,
  ECS_CLUSTER, APP_URL, APP_SUBNET_IDS, DATA_CLIENTS_SG_ID, FRONTEND_BUCKET, CLOUDFRONT_DISTRIBUTION_ID,
  FRONTEND_KVS_ARN, GENAI_ENABLED` (+ `MWAA_BUCKET, MWAA_ENVIRONMENT, QUALITY_BUCKET` with the data platform);
  staging/prod also `SOURCE_ECR_READ_ROLE_ARN, SOURCE_ECR_REGISTRY` (previous env's `gha-ecr-read` role + registry).
  Optional: `SMOKE_BASE_URL` (use the CloudFront domain until DNS exists), `CHANGE_TICKET_PATTERN`.
- **Repository variables** (from `github_repository_variables`): `AWS_REGION`, `TF_PLAN_ROLE_ARN_DEV/_STAGING/_PROD`
  (+ `DATABRICKS_*_<ENV>`, `MODEL_CATALOG_<ENV>` with the data platform).

```powershell
.\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment dev
.\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment staging -ReviewerTeams <ey-leads> `
  -SourceEcrReadRoleArn arn:aws:iam::<dev-acct>:role/mmm-dev-gha-ecr-read -SourceEcrRegistry <dev-acct>.dkr.ecr.<region>.amazonaws.com
.\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment prod -ReviewerTeams <wbd-approvers> `
  -SourceEcrReadRoleArn arn:aws:iam::<stg-acct>:role/mmm-stg-gha-ecr-read -SourceEcrRegistry <stg-acct>.dkr.ecr.<region>.amazonaws.com
```

Note: team reviewers need an **organisation** repo; a personal repo can only use `-ReviewerUsers`.

---

## 9. Order of work once the values arrive

1. Fix defects D1–D4 (section 5.1); decide which gaps in 5.2/5.3 to build.
2. Fill dev values (section 6) – `terraform.tfvars`, `infra/bootstrap/dev.tfvars`, `backend.tf`.
3. `aws configure sso` for dev (`docs/02`); check `aws sts get-caller-identity`.
4. Bootstrap state: `cd infra/bootstrap; terraform init; terraform apply -var-file=dev.tfvars`; copy the bucket and `state_kms_key_arn` into `infra/environments/dev/backend.tf` and `terraform.tfvars`.
5. Make sure the ACM certificates are ISSUED.
6. First apply of dev from the laptop (`infra/environments/dev`: `terraform init`, `plan -out`, `apply`). Confirm the SNS email subscriptions.
7. Give WBD DNS the records from `terraform output dns_records_for_wbd`.
8. `setup-github.ps1` for dev → from now on Terraform runs from GitHub Actions.
9. DB bootstrap (section 7) to fill `rds/migrate`, `rds/proxy`, `api/db`.
10. When the app teams merge `apps/*`: CI builds `sha-<7>` → `deploy.yml` deploys to dev (migration, update, smoke, rollback on failure).
11. Run each step's "Validate" section in `infra/environments/dev/README.md` (Steps 3–11).
12. Repeat 2–9 for staging (tag `vX.Y.Z-rcN`), then prod (tag `vX.Y.Z` with change ticket) – `infra/environments/staging|prod/README.md`.
13. Step 13: data platform values → `enable_data_platform = true` → validate (`docs/10`).
14. Release 1 gate: `docs/11` (pen test, restore test, failover, performance, UAT, sign-offs).
15. Step 14 only after WBD approves Release 2: GenAI values → `enable_genai = true` → `GENAI_ENABLED=true` (`docs/12`).
16. Step 15: KT sessions and handover checklist (`docs/13`).

---

## 10. Session history (for context)

1. Earlier sessions (lost): Steps 0–13 implemented; pushed to GitHub as commits `52369fa` (Steps 0–13) and `848dab8` (CI fixes).
2. 4 Nov 2026: tools reinstalled; Release 1 gate pack (`docs/11`); Step 14 (GenAI) and Step 15 (handover) implemented and validated offline; secret-scan script now skips local caches; reviewed against `devops_plan_1.txt`, the docx and the xlsx (sections 5.2–5.3); pushed commit `211f89a`; this file created.
3. The user chose not to fix the gaps yet (to be done when real values arrive).

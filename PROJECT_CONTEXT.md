# WBD MMM DevOps – Project Context and Continuation Guide

> **To start a new chat, attach [`Project_memory.md`](Project_memory.md)** – the single file with
> everything in this document plus the working rules, chat history, lessons learned and the process
> for the next requirement. This file is kept as the technical reference other docs link to.

Last updated: 5 Nov 2026 (v2 architecture from `wbd_Presentation.pptx` implemented and validated
offline; pushed to `main` as `89382f2` + `bf4a051`).

---

## 0. How to resume in a new chat

Preferred: attach `Project_memory.md` and use the prompt in its section 0. Otherwise paste this:

> I'm continuing the WBD MMM DevOps project. Read `PROJECT_CONTEXT.md` in the project root first:
> it lists what is done, the decisions taken, the open gaps and the next steps. The project is at
> `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`
> and on GitHub at https://github.com/Yashwanth-wbd/wbd-aws-devops. Follow the rules in section 3.
> Today I want to: <say what – e.g. "commit the v2 changes", "fill the real dev values I have">.

If the tools are missing after a VDI reset, ask the agent to run section 3.1 first.

---

## 1. Project snapshot

| Item | Value |
|---|---|
| What | DevOps for the WBD Media-Mix-Modeling (MMM) platform: Terraform, ECS task definitions, GitHub Actions CI/CD, scripts, runbooks. App, data-engineering and model code belong to the WBD / EY teams – nothing app-side is in this repo. |
| Project folder (source of truth) | `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1` (note the spelling *implmenetation*) |
| GitHub repo | https://github.com/Yashwanth-wbd/wbd-aws-devops – branch `main`, v2 pushed on 5 Nov 2026 (`89382f2` implementation, `bf4a051` CI guards); all push workflows green. Commit only when the user asks. |
| GitHub login | `gh` CLI logged in as `Yashwanth-wbd` (keyring). After a VDI reset run `gh auth login --web --scopes repo,workflow` again. |
| Requirement documents (`docs/requirements/`) | **`wbd_Presentation.pptx`** (new v2 target architecture – the one being followed), `devops_plan_2.txt` (v2 plan: v1 → v2 delta, decisions), `aws_resource_list_2.xlsx` (v2 resources per env), `wbd_mmm_ecs_final_2.docx` (v2 design doc), `PROJECT_CONTEXT_2.md` (v2 planning context). v1 inputs kept for history: `devops_plan_1.txt`, `devops_plan.txt`, `wbd_mmm_ecs_final.docx`, `aws_resource_list.xlsx`, `wbd_final.docx` (RFP, confidential), `wbd_0.docx`, `wbd_1.docx` |
| AWS accounts | Not provided yet: `wbd-mmm-dev`, `wbd-mmm-stage`, `wbd-mmm-prod` (placeholders `111111111111`, `222222222222`, `333333333333`) |
| Status | **v2 implemented with placeholder values and validated offline** (fmt, validate, mock plan of all 3 envs). Nothing applied to AWS. Real validation waits for client values, accounts and the app code. |

### 1.1 v2 architecture in one paragraph

Planners sign in at **WBD Okta (SAML) → Cognito user pool → ALB `authenticate-cognito`** behind a
**regional WAF**. The ALB routes `/` to the **`ui`** ECS service and `/api/*` to the **`api`** ECS
service (Fargate). What-if runs in the API; an optimization run is an **async Step Functions
execution** (`mmm-<env>-optimization`) that starts a **SageMaker Processing job** (image
`mmm/sagemaker-optimizer`, current URI in SSM) and then the **results-publisher Lambda**, which
writes the result to **Aurora PostgreSQL Serverless v2** through **RDS Proxy** (IAM auth). With the
data platform, **EventBridge Scheduler / an `mmm.refresh` event** starts `mmm-<env>-model-refresh`:
Databricks job (features) → SageMaker training → evaluation → **SageMaker Model Registry**
(`PendingManualApproval`); `model-governance.yml` checks thresholds and a WBD approver approves,
which publishes the response curves the optimizer reads. Release 2 GenAI: **private API Gateway
LLM gateway** → OpenAI / Anthropic / Google with **Bedrock Guardrails** (`ApplyGuardrail`).

### 1.2 What v2 removed

CloudFront (+ KVS, OAC, us-east-1 WAF/cert, origin-verify secret, S3 frontend bucket), RDS instance,
ElastiCache Valkey, SQS FIFO + DLQ, `whatif-worker` / `optimizer-worker` services, MWAA + data-trigger
Lambda + DAGs + `data.yml`, MLflow/Unity Catalog model aliases, `genai-gateway` ECS service and the
old `bedrock` module. Modules deleted: `rds`, `elasticache`, `sqs`, `edge`, `mwaa`, `data-trigger`,
`bedrock`.

---

## 2. Decisions taken (keep these unless the client says otherwise)

| Topic | Decision | Why / where documented |
|---|---|---|
| Container registry | **One ECR per environment**; CI pushes to dev ECR, promotion copies the same digest to staging (`vX.Y.Z-rcN`) and prod (`vX.Y.Z`) with `skopeo` | `README.md`, `docs/09` |
| Shared/tooling account | **Not built** | GitHub-hosted runners make it unnecessary. **Needs confirmation with WBD** |
| CI runners | GitHub-hosted (`ubuntu-latest`) | `docs/00` |
| Repository layout | Single repo (infra + pipelines + ecs + data hooks + docs) | |
| Account security baseline | CloudTrail, GuardDuty, Security Hub, Config, SCPs, … **owned by WBD, only verified** | `docs/01` |
| Terraform state lock | S3 native lock file (`use_lockfile = true`) | `infra/bootstrap/README.md` |
| Front door | **No CloudFront.** Public ALB + regional WAF; `alb_ingress_cidrs` default `0.0.0.0/0` (WAF + Cognito protect it); set WBD ranges to restrict | `infra/modules/alb`, `waf-regional` |
| Sign-in | **Cognito federated to Okta via SAML** (simplest ALB-native option, no app secret in the UI); MFA enforced in Okta; groups via SAML attribute `groups` → `custom:groups` | `docs/04` |
| App DNS | Route 53 alias only if `route53_zone_id` is set; otherwise WBD DNS adds the CNAME from `dns_records_for_wbd` | `docs/01` |
| UI hosting | **`ui` ECS Fargate container** (React served by the container, `/healthz`), image `mmm/ui` | `ecs/dev/ui.json` |
| Database | **Aurora PostgreSQL Serverless v2** 16.6 + RDS Proxy (IAM auth, TLS). dev 1 instance 0.5–4 ACU; staging 2 × 0.5–16; prod 2 × 1–32 | `infra/modules/aurora` |
| Cache / queue | **None.** Step Functions executions replace the queue (idempotent by `run_id`); progress = DescribeExecution + run row in Aurora | `optimization.tf` |
| Optimization engine | Step Functions → SageMaker Processing (`createProcessingJob.sync`) → Lambda publisher (`live` alias) | `optimization.tf` |
| Image versions for SageMaker | SSM pointer `/mmm/<env_short>/images/sagemaker-*` = `<registry>/<repo>@<digest>`, written by `deploy.yml`; Terraform ignores the value | `optimization.tf`, `deploy.yml` |
| Data orchestration | **No MWAA.** EventBridge Scheduler (per BU) + on-demand `mmm.refresh` event → Step Functions HTTP Task → Databricks Jobs API via an **EventBridge connection** (OAuth client credentials) | `data.tf` |
| Model registry | **SageMaker Model Registry** per BU (`<prefix>-<bu>`); approval via `model-governance.yml` + `<env>-model-promotion` environment; approval publishes curves to `models/curves/<bu>/` | `docs/10` §7 |
| Databricks code | Asset Bundle in `data/databricks/` (data engineers) deployed by `databricks.yml` with GitHub OIDC federation | `docs/10` |
| GenAI (Release 2) | Built but **off** (`enable_genai = false`): private API Gateway + proxy Lambda to approved providers; Bedrock guardrail on every call | `docs/12` |
| Data platform | Built but **off** (`enable_data_platform = false`) | `docs/10` |
| Splunk token | Secrets Manager `mmm/<env>/splunk/hec` | `docs/05` |
| Authorization | App RBAC by Okta group + PostgreSQL row-level security per BU | `docs/06` |
| Placeholders | Every placeholder has `# add actual value` on the line above | `README.md` |
| Naming / tags | `mmm-<env>-<component>`, env = `dev`/`stg`/`prd`; tags Application, Environment, Owner, BusinessUnit, DataClassification, ManagedBy, Component (CostCenter removed) | `README.md` |

---

## 3. Working rules and local environment

**Rules for any change**
1. DevOps only – never write api / ui / data-engineering / model code.
2. No secrets in Git, images or Terraform variables.
3. Terraform is applied by GitHub Actions through OIDC. Exceptions: the one-time state bootstrap and the **first apply** of each account – run from a laptop with SSO.
4. Edit only `infra/environments/dev/*.tf` and `ecs/dev/*.json`, then run `.\scripts\sync-environments.ps1` (it also deletes staging/prod files that no longer exist in dev; CI fails if they differ). `terraform.tfvars`, `backend.tf` and `README.md` are per environment.
5. Every placeholder gets `# add actual value` on the line above.
6. Match the existing style and comment density. Do not commit unless asked.

### 3.1 Tools (no admin rights; installed under `C:\Users\yn\tools`)

Reinstall after a VDI reset: `powershell -ExecutionPolicy Bypass -File .\scripts\install-prereqs.ps1`
(uv and actionlint were added by hand: `pip install uv`; actionlint binary into `C:\Users\yn\tools\bin`).

| Tool | Version used |
|---|---|
| Terraform | 1.17.1 (providers: aws 5.100.0, archive 2.8.1, random 3.9.1) |
| AWS CLI | 2.39.3 |
| Git / GitHub CLI | 2.56 / 2.103.3 |
| jq / tflint / Trivy | 1.8.2 / 0.65.0 / 0.76.1 |
| Node / Python / uv | 22.23 / 3.12 / 0.13.7 |
| actionlint / Checkov | 1.7.12 / latest |
| Docker | **not installed** (CI builds images) |

PATH line for every new PowerShell window:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
```

Agent notes: `Select-String` fails on the UNC path (use the editor search); run shell commands with
working directory `C:\Users\yn` and absolute paths.

### 3.2 Fast local copy (the network share is slow for Terraform/git)

```powershell
robocopy "\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1" C:\work\wbd /MIR /XD .terraform .venv
git config --global --add safe.directory '%(prefix)///USE_EIS_NTPCFS1.tw.tweis.net/WMAD_Profiles/yn/Desktop/wbd_devops/wbd_devops_implmenetation_1'
```

### 3.3 Offline validation commands

```powershell
cd infra; terraform fmt -check -recursive; cd ..
.\scripts\sync-environments.ps1 -Check                 # staging/prod = dev
.\scripts\validate-modules.ps1                          # each module validates
.\scripts\mock-plan.ps1 -Environment dev,staging,prod   # terraform test with mocked AWS
tflint --recursive --config "$PWD\.tflint.hcl"
.\scripts\checkov-scan.ps1 -Path .\infra
actionlint
.\scripts\secret-scan.ps1
```

Mock-plan results on 5 Nov 2026 (resources to add):

| Env | Default | All optional features on |
|---|---|---|
| dev | 297 | 430 |
| staging | 314 | 449 |
| prod | 314 | 451 |

---

## 4. What is built

| Area | Content |
|---|---|
| Bootstrap | `infra/bootstrap`: state bucket (versioned, KMS, TLS-only), KMS key |
| Modules (`infra/modules`) | kms, permission-boundary, iam-oidc, budgets, network, secrets, ecr, s3-bucket, log-bucket, **aurora**, ecs-cluster, alb, ecs-service, **cognito**, **waf-regional**, **step-functions**, **sagemaker**, **lambda-function**, monitoring, log-shipping, backup, databricks-access, **bedrock-guardrails**, **llm-gateway** (bold = new in v2). Each has a README |
| Stack files (`infra/environments/<env>`) | `main.tf` (KMS, IAM/OIDC, network, secrets, ECR, buckets, Aurora), `frontdoor.tf` (Cognito, ALB, WAF, Route 53), `ecs.tf` (api, ui, migrate, platform-check), `optimization.tf` (SSM image pointers, SageMaker role, publisher Lambda, optimization state machine), `data.tf` (Databricks access + connection, training side, model-refresh state machine, schedules, on-demand rule), `genai.tf`, `monitoring.tf`, `backup.tf`, `outputs.tf`, `variables.tf`, `tests/mock-plan.tftest.hcl` |
| ECS templates | `ecs/<env>/api.json`, `ui.json`, `migrate.json` |
| Workflows | `api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci` (via `_python-service-ci`, `build_image` input), `deploy` (api, ui, optimizer, training, publisher; promotion, prod Aurora snapshot, migration, smoke, rollback of ECS + SSM pointers + Lambda alias), `terraform` (+ `_terraform-apply`, drift skip when no role), `databricks`, `model-governance`, `repo-checks` |
| Scripts | `smoke.sh` (health + Cognito redirect), `deploy-components.sh`, `lambda-release.sh`, `trigger-model-refresh.sh`, `platform-check.sh`, `model_governance.py` (SageMaker registry), `promote-images.sh`, `ecs-deploy.sh`, `run-migration.sh`, `db-bootstrap.py`, `setup-github.ps1` (`-DatabricksClientId`), `sync-environments.ps1`, `mock-plan.ps1`, `validate-modules.ps1`, `checkov-scan.ps1`, `secret-scan.ps1` |
| Docs | `docs/00`–`13` and `docs/runbooks/` (incl. new `optimization-run-failed.md`) rewritten for v2; env READMEs with "Validate" commands |

v1 defects D1–D4 are fixed: Trivy `version:` on every trivy-action, drift job skips without role,
skopeo installed in `deploy.yml`, `github_org`/`github_repo` = `Yashwanth-wbd`/`wbd-aws-devops`.

---

## 5. Open issues and gaps

### 5.1 Validation and CI status

- Done on 5 Nov 2026: fmt, validate-modules, mock plan (all envs), `sync-environments.ps1 -Check`,
  tflint, Checkov (0 failed, accepted skips have a reason comment), actionlint, secret scan – all clean.
- Executable bit is set on every `scripts/*.sh` in Git; new `.sh` files need `git add --chmod=+x`.
- App CI workflows (`api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci`) skip while the
  app folder is absent; `deploy.yml` deploys only when the triggering CI run's test job succeeded.

### 5.2 Open questions for WBD (implemented with the simpler industry-standard default)

| # | Question | Default implemented |
|---|---|---|
| Q1 | ALB reachable from the internet or only WBD ranges? Shield Advanced? | Internet + WAF + Cognito; `alb_ingress_cidrs` to restrict; no Shield Advanced |
| Q2 | Throttling for 50–150 planners without SQS | Step Functions + SageMaker quotas; API limits concurrent runs per user (app side) |
| Q3 | External LLM providers = data leaves AWS | Behind `enable_genai` + guardrail PII masking/blocking; needs WBD approval |
| Q4 | Databricks workspace IP access list must allow Step Functions HTTP calls (public endpoint) | Confirm with WBD Databricks |
| Q5 | Okta: SAML app per env, group names | `groups` attribute; names `mmm-bu-*` / `mmm-role-*` (docs/04, 06) |
| Q6 | Separate Databricks service principal for bundle deploy (`DATABRICKS_CLIENT_ID`) vs the refresh SP | Two SPs recommended |

### 5.3 Gaps (unchanged from v1 review, still open)

CODEOWNERS (needs team names), DAST (ZAP), SBOM (Syft), image signing (cosign), dev cost
scale-down, performance tests, post-deploy integration tests beyond the optimization dry run,
Synthetics canary, business-continuity page, shared account decision.

### 5.4 Not in this repo but needed before a real deployment works

- App code: `apps/api`, `apps/ui`, `apps/sagemaker-optimizer`, `apps/sagemaker-training`,
  `apps/results-publisher`, and the Databricks bundle `data/databricks/`. Until then the CI jobs
  skip and there is nothing to deploy.
- Real values (section 6), issued ACM certificate, WBD DNS record, Okta SAML apps.

---

## 6. Values to collect from the client and where they go

Full list with owners: `docs/01-client-inputs-tracker.md`. Find every placeholder:
`git grep -n -A1 "add actual value"`. Edit each environment's `terraform.tfvars` separately.

| Area | tfvars / place |
|---|---|
| Accounts, region | `aws_account_id`, `aws_region`, `allowed_regions`, `dr_region`, `backend.tf`, `infra/bootstrap/<env>.tfvars` |
| Network | `vpc_cidr`, `availability_zone_ids`, `enable_nat_gateway`, TGW / resolver values |
| Front door | `app_domain_name`, `alb_certificate_arn` (workload region, ISSUED), `alb_ingress_cidrs`, `route53_zone_id` (optional), `geo_allow_countries`, `waf_count_only` |
| Sign-in | `okta_saml_metadata_url` (one Okta SAML app per env), `cognito_domain_prefix`, `session_hours`; after apply give WBD Okta `terraform output okta_app_settings` |
| Database | `aurora_min_acu`, `aurora_max_acu` (`aurora_engine_version`) |
| Optimization | `optimizer_instance_type`, `optimizer_max_runtime_seconds` |
| Data platform | `databricks_host`, `databricks_account_id`, `databricks_privatelink_service_name`, `databricks_sp_client_id`, `databricks_refresh_job_id`, `training_instance_type`, `model_refresh_schedule` / `_timezone`, `enable_model_refresh_schedule`, `training_data_retention_days`, `data/model-thresholds.yaml`, then `enable_data_platform = true` (UC role two-phase) |
| GenAI | `llm_providers`, `genai_token_quotas`, `genai_reserved_concurrency`, guardrail thresholds, `manage_apigw_account_logging_role`, then `enable_genai = true` |
| Monitoring, budgets, backup | `alert_emails`, `budget_alert_emails`, `monthly_budget_usd`, `splunk_hec_endpoint`, `approved_worm_lock_mode` (irreversible for COMPLIANCE), `approved_worm_retention_days`, prod `enable_vault_lock` / `enable_cross_region_copy` |
| GitHub | reviewer teams/users, model approvers, `-DatabricksClientId`, change-ticket pattern |

---

## 7. Secrets (never in Git – filled in AWS after the first apply)

| Secret / credential | Filled by | When |
|---|---|---|
| Aurora admin password | RDS-managed, auto-rotated | automatic |
| `mmm/<env>/rds/migrate`, `rds/proxy`, `api/db` | DB bootstrap task (`enable_db_bootstrap = true`, apply, run `terraform output -raw db_bootstrap_run_command`, set back to `false`) | before the first migration |
| Databricks client secret | DevOps, on the EventBridge connection `<prefix>-databricks` (`aws events update-connection`, docs/05) | data platform |
| `mmm/<env>/splunk/hec` | WBD Splunk team | before `enable_splunk_shipping = true` |
| `mmm/<env>/thirdparty/<vendor>` | WBD data owners | when the feed is used |
| `mmm/<env>/llm/<provider>` (`{"api_key": "..."}`) | DevOps with WBD-approved keys | before `enable_genai = true` |

GitHub needs **no secrets** (OIDC). Details: `docs/05`.

---

## 8. GitHub configuration

- Environments: `dev` (no reviewers, `main` only), `staging` (EY delivery lead; `main`, `v*`),
  `prod` (WBD approvers, prevent self-review; `main`, `v*`), optional `<env>-model-promotion`
  (WBD model approvers, `main` only).
- **Environment variables** (`terraform output github_environment_variables`, set by `setup-github.ps1`):
  `AWS_REGION, AWS_DEPLOY_ROLE_ARN, ECR_PUSH_ROLE_ARN, TF_PLAN_ROLE_ARN, TF_APPLY_ROLE_ARN, ECR_REGISTRY,
  ECS_CLUSTER, APP_URL, APP_SUBNET_IDS, DATA_CLIENTS_SG_ID, AURORA_CLUSTER_ID, PUBLISHER_FUNCTION,
  OPTIMIZATION_STATE_MACHINE_ARN, SAGEMAKER_IMAGE_PARAM_PREFIX, GENAI_ENABLED` (+ `MODEL_REFRESH_STATE_MACHINE_ARN`,
  `DATABRICKS_HOST` with the data platform; `DATABRICKS_CLIENT_ID` via `-DatabricksClientId`);
  staging/prod also `SOURCE_ECR_READ_ROLE_ARN, SOURCE_ECR_REGISTRY`. Optional `SMOKE_BASE_URL`,
  `SMOKE_CHECK_LOGIN`, `CHANGE_TICKET_PATTERN`.
- **Repository variables** (`github_repository_variables`): `AWS_REGION`, `TF_PLAN_ROLE_ARN_<ENV>`
  (+ `MODEL_EVAL_ROLE_ARN_<ENV>`, `MODEL_APPROVE_ROLE_ARN_<ENV>`, `MODELS_BUCKET_<ENV>` with the data platform).

```powershell
.\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment dev
.\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment staging -ReviewerTeams <ey-leads> `
  -SourceEcrReadRoleArn arn:aws:iam::<dev-acct>:role/mmm-dev-gha-ecr-read -SourceEcrRegistry <dev-acct>.dkr.ecr.<region>.amazonaws.com
.\scripts\setup-github.ps1 -Repo Yashwanth-wbd/wbd-aws-devops -Environment prod -ReviewerTeams <wbd-approvers> `
  -ModelApproverTeams <wbd-model-approvers> `
  -SourceEcrReadRoleArn arn:aws:iam::<stg-acct>:role/mmm-stg-gha-ecr-read -SourceEcrRegistry <stg-acct>.dkr.ecr.<region>.amazonaws.com
```

Note: team reviewers need an **organisation** repo; a personal repo can only use `-ReviewerUsers`.

---

## 9. Order of work once the values arrive

1. (Done) v2 validated and pushed.
2. Fill dev values (section 6) – `terraform.tfvars`, `infra/bootstrap/dev.tfvars`, `backend.tf`.
3. `aws configure sso` for dev (`docs/02`); `aws sts get-caller-identity`.
4. Bootstrap state; copy bucket and `state_kms_key_arn` into `backend.tf` / tfvars.
5. ACM certificate ISSUED in the workload region; Okta SAML app metadata URL from WBD.
6. First apply of dev from the laptop. Confirm the SNS email subscriptions.
7. Give WBD DNS `dns_records_for_wbd` and WBD Okta `okta_app_settings`.
8. `setup-github.ps1` for dev → Terraform runs from GitHub Actions from now on.
9. DB bootstrap (section 7).
10. When the app teams merge `apps/*`: CI builds `sha-<7>` → `deploy.yml` deploys to dev.
11. Run the "Validate" sections in `infra/environments/dev/README.md`.
12. Staging (tag `vX.Y.Z-rcN`), then prod (tag `vX.Y.Z` with change ticket).
13. Data platform values → `enable_data_platform = true` → validate (`docs/10`).
14. Release 1 gate (`docs/11`); Release 2 GenAI only after WBD approval (`docs/12`); handover (`docs/13`).

---

## 10. Session history

1. Earlier sessions: v1 Steps 0–15 implemented and pushed (`52369fa`, `848dab8`, `211f89a`).
2. 4 Nov 2026: Release 1 gate pack, GenAI, handover, reviews; this file created.
3. 5 Nov 2026: v2 requirement (`wbd_Presentation.pptx`) reviewed, plan and `_2` documents written,
   then v2 implemented: services removed / added as listed in 1.2 and 4, D1–D4 fixed, docs rewritten,
   offline validation passed; pushed to `main` (`89382f2`), then CI guards for absent app folders
   and a shellcheck fix (`bf4a051`); all push workflows green. `Project_memory.md` (single
   file to attach to a new chat) and `docs/requirements/tools/` (doc generator scripts) added.
4. 5 Nov 2026: review against `devops_plan_2.txt`, then the missing plan items were built: Step 9
   alarms and dashboards, backup of `training-data` / `lakehouse`, post-release optimization dry run,
   actions pinned to commit SHAs; doc and xlsx corrections. Details: `Project_memory.md` §5 and §12.

# WBD MMM DevOps – Project Context and Continuation Guide

> **To start a new chat, attach [`Project_memory.md`](Project_memory.md)** – the single file with
> everything in this document plus the working rules, chat history, lessons learned and the process
> for the next requirement. This file is kept as the technical reference other docs link to.

Last updated: 6 Nov 2026 (v3 architecture from `wbd_Presentation_3.pptx` implemented and validated
offline, pushed to `main` as `59333f0`; v2 was `89382f2` + `bf4a051`).

> **v4 (12 Nov 2026) supersedes parts of this file.** The optimizer is now an ECS Fargate task
> (`mmm/optimizer`, SSM `ecs/optimizer_task_definition`) instead of a SageMaker Processing job; user
> input files go to the new `uploads` bucket; Databricks is only the source (export Lambda + write-only
> UC role) and the lakehouse runs on **Glue** (bronze → silver with Data Quality → gold → exports);
> model results go to RDS through the publisher instead of a Databricks write-back; the EventBridge
> connection, `databricks.yml`, `DATABRICKS_CLIENT_ID` / `-DatabricksClientId`,
> `databricks_sp_client_id` / `_refresh_job_id` / `_writeback_job_id` and `optimizer_instance_type` are
> gone. Current state: [`Project_memory.md`](Project_memory.md) sections 1.0 / 1.0a and
> [`docs/requirements/PROJECT_CONTEXT_4.md`](docs/requirements/PROJECT_CONTEXT_4.md); details in
> `docs/09`, `docs/10`.

---

## 0. How to resume in a new chat

Preferred: attach `Project_memory.md` and use the prompt in its section 0. Otherwise paste this:

> I'm continuing the WBD MMM DevOps project. Read `PROJECT_CONTEXT.md` in the project root first:
> it lists what is done, the decisions taken, the open gaps and the next steps. The project is at
> `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`
> and on GitHub at https://github.com/Yashwanth-wbd/wbd-aws-devops. Follow the rules in section 3.
> Today I want to: <say what – e.g. "commit the v3 changes", "fill the real dev values I have">.

If the tools are missing after a VDI reset, ask the agent to run section 3.1 first.

---

## 1. Project snapshot

| Item | Value |
|---|---|
| What | DevOps for the WBD Media-Mix-Modeling (MMM) platform: Terraform, ECS task definitions, GitHub Actions CI/CD, scripts, runbooks. App, data-engineering and model code belong to the WBD / EY teams – nothing app-side is in this repo. |
| Project folder (source of truth) | `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1` (note the spelling *implmenetation*) |
| GitHub repo | https://github.com/Yashwanth-wbd/wbd-aws-devops – branch `main`, v2 pushed on 5 Nov 2026 (`89382f2` implementation, `bf4a051` CI guards); all push workflows green. Commit only when the user asks. |
| GitHub login | `gh` CLI logged in as `Yashwanth-wbd` (keyring). After a VDI reset run `gh auth login --web --scopes repo,workflow` again. |
| Requirement documents (`docs/requirements/`) | **`wbd_Presentation_3.pptx`** (v3 target architecture – the one being followed), `devops_plan_3.txt` (v3 plan: v2 → v3 delta, decisions), `aws_resource_list_3.xlsx` (v3 resources per env), `wbd_mmm_ecs_final_3.docx` (v3 design doc), `PROJECT_CONTEXT_3.md` (v3 planning context). v2 inputs kept for history: `wbd_Presentation.pptx`, `devops_plan_2.txt`, `aws_resource_list_2.xlsx`, `wbd_mmm_ecs_final_2.docx`, `PROJECT_CONTEXT_2.md`. v1 inputs kept for history: `devops_plan_1.txt`, `devops_plan.txt`, `wbd_mmm_ecs_final.docx`, `aws_resource_list.xlsx`, `wbd_final.docx` (RFP, confidential), `wbd_0.docx`, `wbd_1.docx` |
| AWS accounts | Not provided yet: `wbd-mmm-dev`, `wbd-mmm-stage`, `wbd-mmm-prod` (placeholders `111111111111`, `222222222222`, `333333333333`) |
| Status | **v3 implemented with placeholder values and validated offline** (fmt, validate, mock plan of all 3 envs). Nothing applied to AWS. Real validation waits for client values, accounts and the app code. |

### 1.1 v3 architecture in one paragraph

Planners sign in with **WBD Okta over OIDC directly at the ALB (`authenticate-oidc`)** behind a
**regional WAF**; until `okta_sign_in_enabled = true` the ALB answers 503. The ALB routes `/` to the
**`ui`** ECS service and `/api/*` to the **`api`** ECS service (Fargate). What-if runs in the API; an
optimization request goes to the **SQS run queue** (`<prefix>-optimization-requests`, DLQ after
~60 min); the **run-dispatcher Lambda** starts at most `max_concurrent_runs` (SSM) **Step Functions
executions** (`mmm-<env>-optimization`) at a time, each starting a **SageMaker Processing job**
(image `mmm/sagemaker-optimizer`, current URI in SSM) and then the **results-publisher Lambda**,
which writes the result to **RDS PostgreSQL** (Multi-AZ in staging / prod) through **RDS Proxy**
(IAM auth). With the data platform, **EventBridge Scheduler / an `mmm.refresh` event** starts
`mmm-<env>-model-refresh`: Databricks job (features) → SageMaker training → evaluation →
**SageMaker Model Registry** (`PendingManualApproval`) → **Databricks write-back** of predictions and
lift; `model-governance.yml` checks thresholds and a WBD approver approves, which publishes the
response curves and drift baseline and writes `approval.json`. **`mmm-<env>-model-monitor`** runs per
BU on a daily schedule, scores drift against the baseline, publishes `MMM/Models ModelDrift` and alarms
when the score passes the threshold (it also requests a refresh if `auto_refresh_on_drift = true`). Release 2 GenAI: **private API Gateway LLM gateway** →
OpenAI / Anthropic / Google with **Bedrock Guardrails** (`ApplyGuardrail`).

### 1.2 What v3 changed

Removed: Cognito user pool, domain and SAML identity provider (module `cognito`), Aurora PostgreSQL
Serverless v2 (module `aurora`), runbook `cognito-idp-outage.md`, GitHub variable `AURORA_CLUSTER_ID`.
Added: module `rds` (RDS PostgreSQL + RDS Proxy), module `run-queue` (SQS + DLQ + dispatcher Lambda +
alarms), ALB `authenticate-oidc` with secret `mmm/<env>/okta/alb-client`, KMS key `sqs`, SQS VPC
endpoint, Databricks write-back states, `model-monitor` state machine + per-BU drift schedules and
alarms, governance baseline + `approval.json`, GitHub variables `DB_INSTANCE_ID`,
`OPTIMIZATION_QUEUE_URL`, `SMOKE_CHECK_LOGIN`, runbooks `okta-outage`, `write-back-failed`,
`model-drift`.

### 1.3 What v2 removed (history)

CloudFront (+ KVS, OAC, us-east-1 WAF/cert, origin-verify secret, S3 frontend bucket), RDS instance,
ElastiCache Valkey, SQS FIFO + DLQ, `whatif-worker` / `optimizer-worker` services, MWAA + data-trigger
Lambda + DAGs + `data.yml`, MLflow/Unity Catalog model aliases, `genai-gateway` ECS service and the
old `bedrock` module. Modules deleted: `rds`, `elasticache`, `sqs`, `edge`, `mwaa`, `data-trigger`,
`bedrock`. (v3 brought back an RDS instance and a standard SQS queue as new modules `rds` and
`run-queue`.)

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
| Front door | **No CloudFront.** Public ALB + regional WAF; `alb_ingress_cidrs` default `0.0.0.0/0` (WAF + Okta sign-in protect it); set WBD ranges to restrict | `infra/modules/alb`, `waf-regional` |
| Sign-in | **Okta OIDC at the ALB** (`authenticate-oidc`, scopes `openid profile email groups`); one Okta OIDC web app per env; client secret in `mmm/<env>/okta/alb-client`, read by Terraform; `okta_sign_in_enabled` switch (503 until on); MFA enforced in Okta; groups claim `groups` | `docs/04` |
| App DNS | Route 53 alias only if `route53_zone_id` is set; otherwise WBD DNS adds the CNAME from `dns_records_for_wbd` | `docs/01` |
| UI hosting | **`ui` ECS Fargate container** (React served by the container, `/healthz`), image `mmm/ui` | `ecs/dev/ui.json` |
| Database | **RDS PostgreSQL** 16.6 + RDS Proxy (IAM auth, TLS). dev `db.t4g.medium` Single-AZ, staging `db.r6g.large` Multi-AZ, prod `db.r6g.xlarge` Multi-AZ; gp3 with storage autoscaling; PITR 7 / 14 / 35 days | `infra/modules/rds` |
| Cache / queue | No cache. **Standard SQS run queue + DLQ** (KMS key `sqs`) in front of Step Functions; dispatcher Lambda keeps running executions ≤ `max_concurrent_runs` (5 / 20 / 50, soft limit, SSM); requests expire after `max_queue_wait_minutes` (30) | `run-queue.tf`, `infra/modules/run-queue` |
| Optimization engine | SQS → dispatcher Lambda → Step Functions (idempotent by `run_id`) → SageMaker Processing (`createProcessingJob.sync`) → Lambda publisher (`live` alias) | `optimization.tf` |
| Image versions for SageMaker | SSM pointer `/mmm/<env_short>/images/sagemaker-*` = `<registry>/<repo>@<digest>`, written by `deploy.yml`; Terraform ignores the value | `optimization.tf`, `deploy.yml` |
| Data orchestration | **No MWAA.** EventBridge Scheduler (per BU) + on-demand `mmm.refresh` event → Step Functions HTTP Task → Databricks Jobs API via an **EventBridge connection** (OAuth client credentials) | `data.tf` |
| Model registry | **SageMaker Model Registry** per BU (`<prefix>-<bu>`); approval via `model-governance.yml` + `<env>-model-promotion` environment; approval publishes curves to `models/curves/<bu>/`, the drift baseline to `models/baseline/<bu>/` and writes `approval.json` | `docs/10` §7 |
| Write-back and drift | After registration, a Databricks write-back job (`databricks_writeback_job_id`) loads predictions and lift; `model-monitor` per BU (`model_monitor_schedule`, off until baselines exist) alarms on `ModelDrift` above `drift.threshold`; sends `mmm.refresh` only with `auto_refresh_on_drift = true` (default alert only) | `data.tf`, `docs/10` |
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

Mock-plan results on 6 Nov 2026, v3 (resources to add):

| Env | Default | All optional features on |
|---|---|---|
| dev | 311 | 459 |
| staging | 326 | 476 |
| prod | 326 | 478 |

---

## 4. What is built

| Area | Content |
|---|---|
| Bootstrap | `infra/bootstrap`: state bucket (versioned, KMS, TLS-only), KMS key |
| Modules (`infra/modules`) | kms, permission-boundary, iam-oidc, budgets, network, secrets, ecr, s3-bucket, log-bucket, **rds**, ecs-cluster, alb, ecs-service, waf-regional, step-functions, **run-queue**, sagemaker, lambda-function, monitoring, log-shipping, backup, databricks-access, bedrock-guardrails, llm-gateway (bold = new in v3). Each has a README |
| Stack files (`infra/environments/<env>`) | `main.tf` (KMS, IAM/OIDC, network, secrets, ECR, buckets, RDS), `frontdoor.tf` (Okta OIDC on the ALB, ALB, WAF, Route 53), `ecs.tf` (api, ui, migrate, platform-check), `optimization.tf` (SSM image pointers, SageMaker role, publisher Lambda, optimization state machine), `run-queue.tf` (run queue, dispatcher, SSM run limit), `data.tf` (Databricks access + connection, training side, model-refresh state machine with write-back, model-monitor state machine, schedules, on-demand rule), `genai.tf`, `monitoring.tf`, `backup.tf`, `outputs.tf`, `variables.tf`, `tests/mock-plan.tftest.hcl` |
| ECS templates | `ecs/<env>/api.json`, `ui.json`, `migrate.json` |
| Workflows | `api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci` (via `_python-service-ci`, `build_image` input), `deploy` (api, ui, optimizer, training, publisher; promotion, prod RDS snapshot, migration, smoke, optimization dry run through the queue, rollback of ECS + SSM pointers + Lambda alias), `terraform` (+ `_terraform-apply`, drift skip when no role; also runs on `data/model-thresholds.yaml`), `databricks`, `model-governance` (curves + baseline + `approval.json`), `repo-checks` |
| Scripts | `smoke.sh` (health + Okta redirect when `SMOKE_CHECK_LOGIN`), `dry-run-optimization.sh` (sends a request to the run queue), `deploy-components.sh`, `lambda-release.sh`, `trigger-model-refresh.sh`, `platform-check.sh` (queue, RDS Proxy), `model_governance.py` (SageMaker registry, thresholds, baseline, approval record), `promote-images.sh`, `ecs-deploy.sh`, `run-migration.sh`, `db-bootstrap.py`, `setup-github.ps1` (`-DatabricksClientId`), `sync-environments.ps1`, `mock-plan.ps1`, `validate-modules.ps1`, `checkov-scan.ps1`, `secret-scan.ps1` |
| Docs | `docs/00`–`13` and `docs/runbooks/` updated for v3 (new `okta-outage.md`, `write-back-failed.md`, `model-drift.md`; `db-restore.md` rewritten for RDS); `data/README.md` holds the evaluation, write-back and monitor contracts; env READMEs with "Validate" commands |

v1 defects D1–D4 are fixed: Trivy `version:` on every trivy-action, drift job skips without role,
skopeo installed in `deploy.yml`, `github_org`/`github_repo` = `Yashwanth-wbd`/`wbd-aws-devops`.

---

## 5. Open issues and gaps

### 5.1 Validation and CI status

- Done on 6 Nov 2026 (v3): fmt, validate-modules (24), mock plan (all envs), `sync-environments.ps1 -Check`,
  tflint, Checkov (1323 passed, 0 failed, accepted skips have a reason comment), actionlint, shellcheck,
  secret scan, `model_governance.py check-thresholds` – all clean.
- Executable bit is set on every `scripts/*.sh` in Git; new `.sh` files need `git add --chmod=+x`.
- App CI workflows (`api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci`) skip while the
  app folder is absent; `deploy.yml` deploys only when the triggering CI run's test job succeeded.

### 5.2 Open questions for WBD (implemented with the simpler industry-standard default)

| # | Question | Default implemented |
|---|---|---|
| Q1 | ALB reachable from the internet or only WBD ranges? Shield Advanced? | Internet + WAF + Okta sign-in; `alb_ingress_cidrs` to restrict; no Shield Advanced |
| Q2 | Concurrent optimization runs per environment and how long a request may wait | `max_concurrent_runs` 5 / 20 / 50 (soft limit), `max_queue_wait_minutes` 30; per-user limits stay app side |
| Q3 | External LLM providers = data leaves AWS | Behind `enable_genai` + guardrail PII masking/blocking; needs WBD approval |
| Q4 | Databricks workspace IP access list must allow Step Functions HTTP calls (public endpoint) | Confirm with WBD Databricks |
| Q5 | Okta: OIDC web app per env, issuer (org or custom authorization server), group names, logout with `client_id` | `groups` claim; names `mmm-bu-*` / `mmm-role-*` (docs/04, 06) |
| Q6 | Separate Databricks service principal for bundle deploy (`DATABRICKS_CLIENT_ID`) vs the refresh SP | Two SPs recommended |
| Q7 | RDS instance sizes and Multi-AZ in dev | dev Single-AZ `db.t4g.medium`; staging / prod Multi-AZ `db.r6g.large` / `db.r6g.xlarge` |
| Q8 | Drift checks, threshold and schedule | `drift.threshold` 0.2 per BU in `data/model-thresholds.yaml` (overrides `model_drift_threshold`); monitor schedule off until the first approved baseline |

### 5.3 Gaps (unchanged from v1 review, still open)

CODEOWNERS (needs team names), DAST (ZAP), SBOM (Syft), image signing (cosign), dev cost
scale-down, performance tests, post-deploy integration tests beyond the optimization dry run,
Synthetics canary, business-continuity page, shared account decision.

### 5.4 Not in this repo but needed before a real deployment works

- App code: `apps/api`, `apps/ui`, `apps/sagemaker-optimizer`, `apps/sagemaker-training`,
  `apps/results-publisher`, and the Databricks bundle `data/databricks/`. Until then the CI jobs
  skip and there is nothing to deploy.
- Real values (section 6), issued ACM certificate, WBD DNS record, Okta OIDC apps (client ID + secret).
- Databricks write-back and monitor export jobs (data engineers) and the drift-check code in the training image (model team), following `data/README.md`.

---

## 6. Values to collect from the client and where they go

Full list with owners: `docs/01-client-inputs-tracker.md`. Find every placeholder:
`git grep -n -A1 "add actual value"`. Edit each environment's `terraform.tfvars` separately.

| Area | tfvars / place |
|---|---|
| Accounts, region | `aws_account_id`, `aws_region`, `allowed_regions`, `dr_region`, `backend.tf`, `infra/bootstrap/<env>.tfvars` |
| Network | `vpc_cidr`, `availability_zone_ids`, `enable_nat_gateway`, TGW / resolver values |
| Front door | `app_domain_name`, `alb_certificate_arn` (workload region, ISSUED), `alb_ingress_cidrs`, `route53_zone_id` (optional), `geo_allow_countries`, `waf_count_only` |
| Sign-in | `okta_issuer`, `okta_client_id` (one Okta OIDC app per env; redirect from `terraform output okta_app_settings`), `session_hours`; secret `mmm/<env>/okta/alb-client`, then `okta_sign_in_enabled = true` |
| Database | `rds_instance_class`, `rds_allocated_storage`, `rds_max_allocated_storage`, `rds_multi_az` (`rds_engine_version`) |
| Optimization | `optimizer_instance_type`, `optimizer_max_runtime_seconds`, `max_concurrent_runs`, `max_queue_wait_minutes` |
| Data platform | `databricks_host`, `databricks_account_id`, `databricks_privatelink_service_name`, `databricks_sp_client_id`, `databricks_refresh_job_id`, `databricks_writeback_job_id`, `training_instance_type`, `model_refresh_schedule` / `_timezone`, `enable_model_refresh_schedule`, `model_monitor_schedule`, `enable_model_monitor_schedule`, `model_drift_threshold`, `auto_refresh_on_drift`, `training_data_retention_days`, `data/model-thresholds.yaml` (incl. `drift.threshold`), then `enable_data_platform = true` (UC role two-phase) |
| GenAI | `llm_providers`, `genai_token_quotas`, `genai_reserved_concurrency`, guardrail thresholds, `manage_apigw_account_logging_role`, then `enable_genai = true` |
| Monitoring, budgets, backup | `alert_emails`, `budget_alert_emails`, `monthly_budget_usd`, `splunk_hec_endpoint`, `approved_worm_lock_mode` (irreversible for COMPLIANCE), `approved_worm_retention_days`, prod `enable_vault_lock` / `enable_cross_region_copy` |
| GitHub | reviewer teams/users, model approvers, `-DatabricksClientId`, change-ticket pattern |

---

## 7. Secrets (never in Git – filled in AWS after the first apply)

| Secret / credential | Filled by | When |
|---|---|---|
| RDS admin password | RDS-managed, auto-rotated | automatic |
| `mmm/<env>/okta/alb-client` (`{"client_secret": "..."}`) | DevOps with the WBD Okta app secret | before `okta_sign_in_enabled = true` |
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
  ECS_CLUSTER, APP_URL, APP_SUBNET_IDS, DATA_CLIENTS_SG_ID, DB_INSTANCE_ID, PUBLISHER_FUNCTION,
  OPTIMIZATION_STATE_MACHINE_ARN, OPTIMIZATION_QUEUE_URL, SMOKE_CHECK_LOGIN, SAGEMAKER_IMAGE_PARAM_PREFIX`
  (+ `RESULTS_BUCKET, MODELS_BUCKET, DRY_RUN_BUSINESS_UNIT` outside prod for the dry run; `MODEL_REFRESH_STATE_MACHINE_ARN`,
  `DATABRICKS_HOST` with the data platform; `DATABRICKS_CLIENT_ID` via `-DatabricksClientId`);
  staging/prod also `SOURCE_ECR_READ_ROLE_ARN, SOURCE_ECR_REGISTRY`. Optional `SMOKE_BASE_URL`,
  `CHANGE_TICKET_PATTERN`. Re-run `setup-github.ps1` after turning Okta sign-in on (updates `SMOKE_CHECK_LOGIN`).
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

1. (Done) v2 validated and pushed; v3 implemented, validated offline and pushed (`59333f0`).
2. Fill dev values (section 6) – `terraform.tfvars`, `infra/bootstrap/dev.tfvars`, `backend.tf`.
3. `aws configure sso` for dev (`docs/02`); `aws sts get-caller-identity`.
4. Bootstrap state; copy bucket and `state_kms_key_arn` into `backend.tf` / tfvars.
5. ACM certificate ISSUED in the workload region; Okta issuer and client ID from WBD.
6. First apply of dev from the laptop (sign-in off, ALB answers 503). Confirm the SNS email subscriptions.
7. Give WBD DNS `dns_records_for_wbd` and WBD Okta `okta_app_settings`; put the Okta client secret in
   `mmm/<env>/okta/alb-client`, set `okta_sign_in_enabled = true`, apply.
8. `setup-github.ps1` for dev → Terraform runs from GitHub Actions from now on.
9. DB bootstrap (section 7).
10. When the app teams merge `apps/*`: CI builds `sha-<7>` → `deploy.yml` deploys to dev.
11. Run the "Validate" sections in `infra/environments/dev/README.md`.
12. Staging (tag `vX.Y.Z-rcN`), then prod (tag `vX.Y.Z` with change ticket).
13. Data platform values → `enable_data_platform = true` → validate (`docs/10`); after the first
    approved model per BU, `enable_model_monitor_schedule = true`.
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
5. 6 Nov 2026: v3 requirement (`wbd_Presentation_3.pptx`) reviewed, `_3` documents written, then v3
   implemented as listed in 1.2: Okta OIDC at the ALB, RDS PostgreSQL, SQS run queue + dispatcher,
   Databricks write-back, model monitor + drift alarms, governance baseline + approval record,
   pipeline and script updates, docs and runbooks. Validated offline; pushed (`59333f0`), workflows green.

# WBD MMM DevOps – Project Memory

**The single file to attach when starting a new chat.** AI chat sessions are lost when the VDI
closes; everything needed to continue (what is built, decisions, how we work, chat history, lessons
learned, next steps) is in this file.

Last updated: 5 Nov 2026 – requirement 2 (v2 architecture from `wbd_Presentation.pptx`)
implemented, validated and pushed to `main` (`89382f2`, `bf4a051`, `9504793`); all GitHub
workflows green.

---

## 0. Start a new chat

Attach **this file** (and, for a new requirement, the new requirement document), then paste:

> I'm continuing the WBD MMM DevOps project. Read the attached `Project_memory.md` first – it has
> everything: what is built, decisions, working rules, history and next steps. Project folder:
> `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`,
> GitHub https://github.com/Yashwanth-wbd/wbd-aws-devops (branch `main`). Follow the rules in section 3.
> Today I want to: <e.g. "review the attached requirement 3 – plan and architecture only, no code yet",
> or "fill the real dev values I have">.

If the tools are gone after a VDI reset, start with: *"reinstall the tools from section 4.1 and log in
to GitHub CLI"*.

At the end of every session ask the agent to **update this file** (sections 1, 6, 11 and 12 at least).

---

## 1. Project snapshot

| Item | Value |
|---|---|
| What | DevOps for the WBD Media-Mix-Modeling (MMM) platform: Terraform, ECS task definitions, GitHub Actions CI/CD, scripts, runbooks. App, data-engineering and model code belong to the WBD / EY teams – nothing app-side is in this repo. |
| Project folder (source of truth) | `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1` (note the spelling *implmenetation*) |
| GitHub repo | https://github.com/Yashwanth-wbd/wbd-aws-devops – branch `main`. Latest: `89382f2` v2 implementation, `bf4a051` CI guards + shellcheck fix, `9504793` context. All push workflows green. |
| GitHub login | `gh` CLI logged in as `Yashwanth-wbd` (keyring). After a VDI reset: `gh auth login --web --scopes repo,workflow` |
| Requirement documents (`docs/requirements/`) | **`wbd_Presentation.pptx`** (v2 target architecture – the one implemented), `devops_plan_2.txt` (v2 plan + implementation status), `aws_resource_list_2.xlsx` (v2 resources per env + "Implemented" column + `decisions` sheet), `wbd_mmm_ecs_final_2.docx` (v2 design doc + implemented defaults), `PROJECT_CONTEXT_2.md` (v2 planning context, section 4a = where the build differs from the plan). v1 inputs kept for history: `devops_plan_1.txt`, `devops_plan.txt`, `wbd_mmm_ecs_final.docx`, `aws_resource_list.xlsx`, `wbd_final.docx` (RFP, confidential), `wbd_0.docx`, `wbd_1.docx`. Generator scripts: `docs/requirements/tools/` |
| AWS accounts | Not provided yet: `wbd-mmm-dev`, `wbd-mmm-stage`, `wbd-mmm-prod` (placeholders `111111111111`, `222222222222`, `333333333333`) |
| Status | **v2 implemented with placeholder values, validated offline, pushed.** Nothing applied to AWS. Real validation waits for client values, accounts and the app code. |

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

### 1.2 What v2 removed (vs v1)

CloudFront (+ KVS, OAC, us-east-1 WAF/cert, origin-verify secret, S3 frontend bucket), RDS instance,
ElastiCache Valkey, SQS FIFO + DLQ, `whatif-worker` / `optimizer-worker` services, MWAA + data-trigger
Lambda + DAGs + `data.yml`, MLflow/Unity Catalog model aliases, `genai-gateway` ECS service and the
old `bedrock` module. Modules deleted: `rds`, `elasticache`, `sqs`, `edge`, `mwaa`, `data-trigger`,
`bedrock`.

### 1.3 Where the build differs from the v2 plan (simpler default chosen)

| Plan | Built |
|---|---|
| Buckets `outputs`, `sagemaker-staging` | Run evidence in the kept `results` bucket (`runs/<run_id>/`); no staging bucket |
| Cognito resource server + groups | Not built – RBAC from the Okta `groups` SAML attribute (`custom:groups`) |
| Publisher Lambda with DLQ | No DLQ – Step Functions invokes the `live` alias synchronously with retries; failures alarm |
| `sagemaker-image-ci` | `optimizer-ci`, `training-ci`, `publisher-ci` via `_python-service-ci` (`build_image` input) |
| LLM gateway: Lambda per provider + usage plans per BU | One proxy Lambda for all providers; stage throttling; per-BU token quotas enforced by the API |
| SageMaker / LLM budgets | Not built – account budget + Cost Anomaly Detection |
| Databricks customer-managed VPC | Not built – WBD workspace; PrivateLink optional (off) |
| `data-v*` tags for Databricks jobs | None – `databricks.yml` deploys the bundle on merge to main (dev) or by dispatch |
| Databricks credentials secret | Held by the EventBridge connection (OAuth client credentials) |
| SageMaker endpoint, Studio, Synthetics, Chatbot, AI-log bucket, GenAI dashboard | Not built |

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
| Sign-in | **Cognito federated to Okta via SAML** (ALB-native, no app secret in the UI); MFA in Okta; groups via SAML attribute `groups` → `custom:groups` | `docs/04` |
| App DNS | Route 53 alias only if `route53_zone_id` is set; otherwise WBD DNS adds the CNAME from `dns_records_for_wbd` | `docs/01` |
| UI hosting | **`ui` ECS Fargate container** (`/healthz`), image `mmm/ui` | `ecs/dev/ui.json` |
| Database | **Aurora PostgreSQL Serverless v2** 16.6 + RDS Proxy (IAM auth, TLS). dev 1 × 0.5–4 ACU; staging 2 × 0.5–16; prod 2 × 1–32 | `infra/modules/aurora` |
| Cache / queue | **None.** Step Functions executions replace the queue (idempotent by `run_id`); progress = DescribeExecution + run row in Aurora | `optimization.tf` |
| Optimization engine | Step Functions → SageMaker Processing (`createProcessingJob.sync`) → Lambda publisher (`live` alias) | `optimization.tf` |
| SageMaker image versions | SSM pointer `/mmm/<env_short>/images/sagemaker-*` = `<registry>/<repo>@<digest>`, written by `deploy.yml`; Terraform ignores the value | `optimization.tf`, `deploy.yml` |
| Instance types | `ml.m5.xlarge` (optimizer / evaluation), `ml.m5.2xlarge` (training); no warm pools | `terraform.tfvars` |
| Autoscaling | CPU target tracking 60 % for api and ui (dev 1–2 / 1–2, stg 2–4 / 2–3, prd 3–10 / 2–6) | `ecs.tf` |
| Data orchestration | **No MWAA.** EventBridge Scheduler (per BU) + on-demand `mmm.refresh` event → Step Functions HTTP Task → Databricks Jobs API via an **EventBridge connection** (OAuth) | `data.tf` |
| Model registry | **SageMaker Model Registry** per BU (`<prefix>-<bu>`); eval role can only reject; approve role (GitHub Environment `<env>-model-promotion`) approves and publishes curves to `models/curves/<bu>/`; rollback re-approves the previous version | `docs/10` §7 |
| Databricks code | Asset Bundle in `data/databricks/` (data engineers) deployed by `databricks.yml` with GitHub OIDC federation | `docs/10` |
| GenAI (Release 2) | Built but **off** (`enable_genai = false`): private API Gateway + proxy Lambda; Bedrock guardrail on every call | `docs/12` |
| Data platform | Built but **off** (`enable_data_platform = false`); per-BU KMS keys `s3-<bu>` come with it | `docs/10` |
| Splunk | CloudWatch primary; Firehose → Splunk built, off; token in `mmm/<env>/splunk/hec` | `docs/05` |
| Authorization | App RBAC by Okta group + PostgreSQL row-level security per BU | `docs/06` |
| Placeholders | Every placeholder has `# add actual value` on the line above | `README.md` |
| Naming / tags | `mmm-<env>-<component>`, env = `dev`/`stg`/`prd`; tags Application, Environment, Owner, BusinessUnit, DataClassification, ManagedBy, Component (CostCenter removed) | `README.md` |

---

## 3. How the user wants to work (keep to this)

1. **Plan first, code later.** New requirement: review → plan + architecture + open questions →
   the user verifies → only then implement. ("Don't add any code unless I verify.")
2. **DevOps only.** Never write api / ui / data-engineering / model code.
3. **Open points:** implement the **simpler, industry-standard default**, record it as an open
   question for WBD, keep going. If something is truly blocking, ask – the user provides it.
4. **Remove what a new requirement drops, add what it introduces** – no leftovers (modules,
   workflows, scripts, docs, ECS templates, tfvars).
5. **After implementing, update the requirement files** (`devops_plan_N.txt`, `PROJECT_CONTEXT_N.md`,
   `aws_resource_list_N.xlsx`, `wbd_mmm_ecs_final_N.docx`) and this file.
6. No secrets in Git, images or Terraform variables.
7. Terraform is applied by GitHub Actions through OIDC. Exceptions: the one-time state bootstrap and
   the **first apply** of each account – run from a laptop with SSO.
8. Edit only `infra/environments/dev/*.tf` and `ecs/dev/*.json`, then run
   `.\scripts\sync-environments.ps1` (also deletes staging/prod files that no longer exist in dev; CI
   fails if they differ). `terraform.tfvars`, `backend.tf` and `README.md` are per environment.
9. Every placeholder gets `# add actual value` on the line above.
10. Match the existing style and comment density.
11. **Commit / push only when asked** (pushes go to `main`; the user approves them in the approval card).
12. Answers in plain language; say clearly what is done and what is not.

---

## 4. Local environment

### 4.1 Tools (no admin rights; installed under `C:\Users\yn\tools`)

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
| shellcheck | via `uvx --from shellcheck-py shellcheck` (not installed) |
| Docker | **not installed** (CI builds images) |

PATH line for every new PowerShell window:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
```

### 4.2 Fast local copy (the network share is slow for Terraform/git)

```powershell
robocopy "\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1" C:\work\wbd /MIR /XD .terraform .venv
git config --global --add safe.directory '%(prefix)///USE_EIS_NTPCFS1.tw.tweis.net/WMAD_Profiles/yn/Desktop/wbd_devops/wbd_devops_implmenetation_1'
```

### 4.3 Offline validation commands

```powershell
cd infra; terraform fmt -check -recursive; cd ..
.\scripts\sync-environments.ps1 -Check                 # staging/prod = dev
.\scripts\validate-modules.ps1                          # each module validates
.\scripts\mock-plan.ps1 -Environment dev,staging,prod   # terraform test with mocked AWS (~7-12 min)
tflint --recursive --config "$PWD\.tflint.hcl"
.\scripts\checkov-scan.ps1 -Path .\infra
actionlint
uvx --from shellcheck-py shellcheck scripts/*.sh        # on an LF copy, see section 10
.\scripts\secret-scan.ps1
```

Mock-plan results on 5 Nov 2026 (resources to add):

| Env | Default | All optional features on |
|---|---|---|
| dev | 287 | 411 |
| staging | 303 | 429 |
| prod | 303 | 431 |

Last run (5 Nov 2026): all of the above clean (Checkov 0 failed; accepted findings have a
`#checkov:skip=<ID>:<reason>` comment).

---

## 5. What is built

| Area | Content |
|---|---|
| Bootstrap | `infra/bootstrap`: state bucket (versioned, KMS, TLS-only), KMS key |
| Modules (`infra/modules`) | kms, permission-boundary, iam-oidc, budgets, network, secrets, ecr, s3-bucket, log-bucket, **aurora**, ecs-cluster, alb, ecs-service, **cognito**, **waf-regional**, **step-functions**, **sagemaker**, **lambda-function**, monitoring, log-shipping, backup, databricks-access, **bedrock-guardrails**, **llm-gateway** (bold = new in v2). Each has a README |
| Stack files (`infra/environments/<env>`) | `main.tf` (KMS, IAM/OIDC, network, secrets, ECR, buckets, Aurora), `frontdoor.tf` (Cognito, ALB, WAF, Route 53), `ecs.tf` (api, ui, migrate, platform-check), `optimization.tf` (SSM image pointers, SageMaker role, publisher Lambda, optimization state machine), `data.tf` (Databricks access + connection, training side, model-refresh state machine, schedules, on-demand rule), `genai.tf`, `monitoring.tf`, `backup.tf`, `outputs.tf`, `variables.tf`, `tests/mock-plan.tftest.hcl` |
| ECS templates | `ecs/<env>/api.json`, `ui.json`, `migrate.json` |
| Workflows | `api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci` (via `_python-service-ci`; skip while the app folder is absent), `deploy` (api, ui, optimizer, training, publisher; promotion, prod Aurora snapshot, migration, smoke, rollback of ECS + SSM pointers + Lambda alias; deploys only when the CI run's test job succeeded), `terraform` (+ `_terraform-apply`, drift skip when no role), `databricks`, `model-governance`, `repo-checks` |
| Scripts | `smoke.sh` (health + Cognito redirect), `deploy-components.sh`, `lambda-release.sh`, `trigger-model-refresh.sh`, `platform-check.sh`, `model_governance.py` (SageMaker registry), `promote-images.sh`, `ecs-deploy.sh`, `run-migration.sh`, `db-bootstrap.py`, `setup-github.ps1` (`-DatabricksClientId`), `sync-environments.ps1`, `mock-plan.ps1`, `validate-modules.ps1`, `checkov-scan.ps1`, `secret-scan.ps1` |
| Docs | `docs/00`–`13` and `docs/runbooks/` (deploy, rollback, scaling, optimization run failed, model refresh failed, Cognito/Okta outage, DB restore, ECS task stuck, rotation, pipeline failure, model rollback, GenAI, security incident, break-glass) |
| Requirement doc tools | `docs/requirements/tools/` – `extract_pptx.py` (slide text + images), `extract.py` (v1 docx/xlsx dump), `build_v2.py` (generates the `_2` xlsx/docx), `check_v2.py`; README explains use |

v1 defects D1–D4 are fixed: Trivy `version:` on every trivy-action, drift job skips without role,
skopeo installed in `deploy.yml`, `github_org`/`github_repo` = `Yashwanth-wbd`/`wbd-aws-devops`.

---

## 6. Open issues and gaps

### 6.1 Open questions for WBD (implemented with the simpler industry-standard default)

| # | Question | Default implemented |
|---|---|---|
| Q1 | ALB reachable from the internet or only WBD ranges? Shield Advanced? | Internet + WAF + Cognito; `alb_ingress_cidrs` to restrict; no Shield Advanced |
| Q2 | Throttling for 50–150 planners without SQS | Step Functions retries on SageMaker limits + app-side concurrency limit per user |
| Q3 | External LLM providers = data leaves AWS | Behind `enable_genai` + guardrail PII masking/blocking; needs written WBD approval |
| Q4 | Databricks workspace IP access list must allow Step Functions HTTP calls | Confirm with WBD Databricks |
| Q5 | Okta: SAML app per env, group names | `groups` attribute; names `mmm-bu-*` / `mmm-role-*` (docs/04, 06) |
| Q6 | Separate Databricks service principal for bundle deploy (`DATABRICKS_CLIENT_ID`) vs the refresh SP | Two SPs recommended |

### 6.2 Gaps (still open)

CODEOWNERS (needs team names), DAST (ZAP), SBOM (Syft), image signing (cosign), dev cost
scale-down, performance tests, post-deploy integration tests, more dashboards / availability alarm,
Synthetics canary, business-continuity page, shared account decision.

### 6.3 Not in this repo but needed before a real deployment works

- App code: `apps/api`, `apps/ui`, `apps/sagemaker-optimizer`, `apps/sagemaker-training`,
  `apps/results-publisher`, and the Databricks bundle `data/databricks/`. Until then the CI jobs
  skip and there is nothing to deploy.
- Real values (section 7), issued ACM certificate, WBD DNS record, Okta SAML apps.
- Dependabot PR #1 (actions updates) was red only because of the missing app folders – rebase it on `main`.

---

## 7. Values to collect from the client and where they go

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

## 8. Secrets (never in Git – filled in AWS after the first apply)

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

## 9. GitHub configuration

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

## 10. Lessons learned / gotchas (save time next session)

| Topic | What to know |
|---|---|
| Network share | The UNC project path is slow; `Select-String` fails on it (use the editor search). Run shell commands from `C:\Users\yn` with absolute paths. For Terraform, tflint, Checkov use the local copy `C:\work\wbd` (section 4.2) |
| PATH | Every new PowerShell needs the PATH line from section 4.1 |
| Mock plan | Takes ~7–12 min; run it in the background |
| Checkov | Accepted findings get `#checkov:skip=<ID>:<reason>` inside the resource (same style as existing ones) |
| Shellcheck | Local files have CRLF: strip `\r` into a temp copy first, otherwise every line reports SC1017. CI checks the LF version in Git |
| Line endings | `.gitattributes` normalizes; CRLF/LF warnings on `git add` are expected |
| Executable bit | New `.sh` files: `git update-index --chmod=+x scripts/<file>.sh` |
| git push | Git cannot prompt for a password here. Push with the `gh` login: `git -c credential.helper= -c "credential.helper=!gh auth git-credential" push origin main` |
| Push approval | The agent's auto-review blocks pushes to `main`; the user approves the push in the approval card |
| App CI | Editing a workflow file triggers its CI; app CIs skip while `apps/<name>` is absent and `deploy.yml` then skips too |
| Requirement docs | xlsx/docx are generated, not hand-edited: edit `docs/requirements/tools/build_v2.py` and re-run it (`uv run --no-project --with openpyxl --with python-docx python build_v2.py <docs/requirements>`) |
| Slides as images | Client decks are mostly images: `extract_pptx.py` saves them; read the images to see the diagrams |
| Python helpers | `uv run --no-project --with <pkg> python <script>` – no installs needed |

---

## 11. Next steps

### 11.1 Process for the next requirement (requirement 3)

1. **Read the new document** (`docs/requirements/tools/extract_pptx.py` for slides, read the images).
2. **Compare with what is built** (sections 1–5 of this file, `infra/modules/README.md`): replacement
   map removed / replaced / new / kept.
3. **Write the plan files** `docs/requirements/devops_plan_3.txt`, `PROJECT_CONTEXT_3.md` and generate
   `aws_resource_list_3.xlsx` + `wbd_mmm_ecs_final_3.docx` (copy `tools/build_v2.py` → `build_v3.py`).
   Mark open points `[ASK]`, assumptions `[ASM]`. **Stop for the user's verification.**
4. **Implement**: new/changed modules (each with a README) → dev stack (`infra/environments/dev`,
   `ecs/dev`) → `sync-environments.ps1` → workflows, scripts, docs, runbooks. Delete what is unused.
5. **Validate** (section 4.3), update the expected mock-plan counts.
6. **Update** the `_3` files with what was built (status, decisions, differences) and this file.
7. **Push when asked**, then check the GitHub Actions runs and fix anything red.

### 11.2 Order of work once the client values arrive

1. Fill dev values (section 7) – `terraform.tfvars`, `infra/bootstrap/dev.tfvars`, `backend.tf`.
2. `aws configure sso` for dev (`docs/02`); `aws sts get-caller-identity`.
3. Bootstrap state; copy bucket and `state_kms_key_arn` into `backend.tf` / tfvars.
4. ACM certificate ISSUED in the workload region; Okta SAML app metadata URL from WBD.
5. First apply of dev from the laptop. Confirm the SNS email subscriptions.
6. Give WBD DNS `dns_records_for_wbd` and WBD Okta `okta_app_settings`.
7. `setup-github.ps1` for dev → Terraform runs from GitHub Actions from now on.
8. DB bootstrap (section 8).
9. When the app teams merge `apps/*`: CI builds `sha-<7>` → `deploy.yml` deploys to dev.
10. Run the "Validate" sections in `infra/environments/dev/README.md`.
11. Staging (tag `vX.Y.Z-rcN`), then prod (tag `vX.Y.Z` with change ticket).
12. Data platform values → `enable_data_platform = true` → validate (`docs/10`).
13. Release 1 gate (`docs/11`); Release 2 GenAI only after WBD approval (`docs/12`); handover (`docs/13`).

---

## 12. Session history

| # | When | User request | Result |
|---|---|---|---|
| 1 | Earlier sessions | Build v1 from `devops_plan_1.txt` (Steps 0–15) | v1 implemented and pushed (`52369fa`, `848dab8`, `211f89a`, …) |
| 2 | 4 Nov 2026 | Release 1 gate pack, GenAI, handover, reviews | Docs 11–13, runbooks; `PROJECT_CONTEXT.md` created |
| 3 | 5 Nov 2026 | Resume, reinstall tools after VDI reset | Tools reinstalled (section 4.1) |
| 4 | 5 Nov 2026 | "Are all things proper?" – review code vs docs, no code changes | Gap review; defects D1–D4 found |
| 5 | 5 Nov 2026 | Log in to GitHub CLI | `gh` logged in as `Yashwanth-wbd` |
| 6 | 5 Nov 2026 | New requirement `wbd_Presentation.pptx` – plan and architecture only | `devops_plan_2.txt`, `PROJECT_CONTEXT_2.md`, `aws_resource_list_2.xlsx`, `wbd_mmm_ecs_final_2.docx` |
| 7 | 5 Nov 2026 | Implement requirement 2; open points with simple industry defaults; remove/add services; DevOps only; update the files | v2 implemented (sections 1–5); D1–D4 fixed; docs/runbooks rewritten; `_2` files updated with implemented status + decisions |
| 8 | 5 Nov 2026 | "Is requirement 2 fully completed?" | DevOps code complete; 2 runbooks added; remaining = client values, AWS apply, app code, Q1–Q6 |
| 9 | 5 Nov 2026 | Push to GitHub | `89382f2` (v2), `bf4a051` (CI guards + shellcheck fix), `9504793` (context); all workflows green |
| 10 | 5 Nov 2026 | Confirm everything is pushed | Local = `origin/main`, nothing uncommitted |
| 11 | 5 Nov 2026 | Keep the chat context in one file | This file (`Project_memory.md`); doc generator scripts moved to `docs/requirements/tools/` |

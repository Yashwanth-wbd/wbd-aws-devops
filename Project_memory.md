# WBD MMM DevOps – Project Memory

**The single file to attach when starting a new chat.** AI chat sessions are lost when the VDI
closes; everything needed to continue (what is built, decisions, how we work, chat history, lessons
learned, next steps) is in this file.

Last updated: 6 Nov 2026 – requirement 3 (v3 architecture from `wbd_Presentation_3.pptx`)
implemented and validated offline; **not committed yet** (v2 is on `main`, latest `35b8a47` plus
memory updates). Commit / push when the user asks.

---

## 0. Start a new chat

Attach **this file** (and, for a new requirement, the new requirement document), then paste:

> I'm continuing the WBD MMM DevOps project. Read the attached `Project_memory.md` first – it has
> everything: what is built, decisions, working rules, history and next steps. Project folder:
> `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`,
> GitHub https://github.com/Yashwanth-wbd/wbd-aws-devops (branch `main`). Follow the rules in section 3.
> Today I want to: <e.g. "commit and push the v3 changes", "review the attached requirement 4 – plan
> and architecture only, no code yet", or "fill the real dev values I have">.

If the tools are gone after a VDI reset, start with: *"reinstall the tools from section 4.1 and log in
to GitHub CLI"*.

At the end of every session ask the agent to **update this file** (sections 1, 6, 11 and 12 at least).

---

## 1. Project snapshot

| Item | Value |
|---|---|
| What | DevOps for the WBD Media-Mix-Modeling (MMM) platform: Terraform, ECS task definitions, GitHub Actions CI/CD, scripts, runbooks. App, data-engineering and model code belong to the WBD / EY teams – nothing app-side is in this repo. |
| Project folder (source of truth) | `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1` (note the spelling *implmenetation*) |
| GitHub repo | https://github.com/Yashwanth-wbd/wbd-aws-devops – branch `main`. Key commits: `89382f2` v2 implementation, `bf4a051` CI guards + shellcheck fix, `d52c7cf` review fixes (alarms, dashboards, backup, dry run, SHA pinning), `87f3b2f` docs (plan differences, slide service map, app team contract), `29ee523` access without admin, `35b8a47` ignore Office lock files. All push workflows green. Check the latest with `git log --oneline -5`. |
| GitHub login | `gh` CLI logged in as `Yashwanth-wbd` (keyring). After a VDI reset: `gh auth login --web --scopes repo,workflow` |
| Requirement documents (`docs/requirements/`) | **`wbd_Presentation_3.pptx`** (v3 target architecture – the one implemented), `devops_plan_3.txt` (v3 plan + implementation status + where the build differs), `aws_resource_list_3.xlsx` (v3 resources per env + column H "v3 implementation" + `removed_vs_v2` and `decisions` sheets), `wbd_mmm_ecs_final_3.docx` (v3 design doc + implemented defaults), `PROJECT_CONTEXT_3.md` (v3 planning context, section 4a = where the build differs from the plan), **`devops_3_client_question.xlsx`** (what WBD must provide – section 7). v2 kept for history: `wbd_Presentation.pptx`, `devops_plan_2.txt`, `aws_resource_list_2.xlsx`, `wbd_mmm_ecs_final_2.docx`, `PROJECT_CONTEXT_2.md`, `devops_2_client_question.xlsx`. v1 inputs kept for history: `devops_plan_1.txt`, `devops_plan.txt`, `wbd_mmm_ecs_final.docx`, `aws_resource_list.xlsx`, `wbd_final.docx` (RFP, confidential), `wbd_0.docx`, `wbd_1.docx`. Generator scripts: `docs/requirements/tools/` |
| AWS accounts | Not provided yet: `wbd-mmm-dev`, `wbd-mmm-stage`, `wbd-mmm-prod` (placeholders `111111111111`, `222222222222`, `333333333333`) |
| Status | **v3 implemented with placeholder values and validated offline; not committed yet.** Nothing applied to AWS. Real validation waits for client values, accounts and the app code. |

### 1.1 v3 architecture in one paragraph

Planners sign in with **WBD Okta over OIDC directly at the ALB (`authenticate-oidc`)** behind a
**regional WAF** (no Cognito); until `okta_sign_in_enabled = true` the ALB answers 503. The ALB
routes `/` to the **`ui`** ECS service and `/api/*` to the **`api`** ECS service (Fargate). What-if
runs in the API; an optimization request goes to the **SQS run queue**
(`<prefix>-optimization-requests` + DLQ); the **run-dispatcher Lambda** starts at most
`max_concurrent_runs` (SSM, soft limit) **Step Functions executions** (`mmm-<env>-optimization`), each
starting a **SageMaker Processing job** (image `mmm/sagemaker-optimizer`, URI in SSM) and then the
**results-publisher Lambda**, which writes to **RDS PostgreSQL** (Multi-AZ in staging / prod) through
**RDS Proxy** (IAM auth). With the data platform, **EventBridge Scheduler / an `mmm.refresh` event**
starts `mmm-<env>-model-refresh`: Databricks job (features) → SageMaker training → evaluation →
**SageMaker Model Registry** (`PendingManualApproval`) → **Databricks write-back** (predictions, lift);
`model-governance.yml` checks thresholds and a WBD approver approves, which publishes the response
curves + drift baseline and writes `approval.json`. **`mmm-<env>-model-monitor`** (daily per BU, off
until the first baseline) scores drift, publishes `MMM/Models ModelDrift`, alarms, and requests a
refresh only with `auto_refresh_on_drift = true`. Release 2 GenAI: **private API Gateway LLM
gateway** → OpenAI / Anthropic / Google with **Bedrock Guardrails** (`ApplyGuardrail`).

### 1.2 What v3 changed (vs v2)

Removed: Cognito (module `cognito`, SSM `cognito/*`, API env `COGNITO_*`), Aurora Serverless v2
(module `aurora`, Aurora alarms / dashboard), runbook `cognito-idp-outage.md`, GitHub variable
`AURORA_CLUSTER_ID`, `states:StartExecution` on the API task role. Added: module `rds` (instance,
parameter group, subnet group, Proxy), module `run-queue` (queue, DLQ, dispatcher Lambda, alarms) +
stack file `run-queue.tf`, ALB `authenticate-oidc`, secret `okta/alb-client`, SSM `okta/issuer` and
`optimization/max_concurrent_runs`, KMS key `sqs`, SQS endpoint, write-back states, model-monitor
state machine + schedules + drift alarms, governance baseline + `approval.json`, GitHub variables
`DB_INSTANCE_ID`, `OPTIMIZATION_QUEUE_URL`, `SMOKE_CHECK_LOGIN`, runbooks `okta-outage`,
`write-back-failed`, `model-drift`. Where the build differs from the v3 plan: `PROJECT_CONTEXT_3.md` §4a.

### 1.2a What v2 removed (vs v1, history)

CloudFront (+ KVS, OAC, us-east-1 WAF/cert, origin-verify secret, S3 frontend bucket), RDS instance,
ElastiCache Valkey, SQS FIFO + DLQ, `whatif-worker` / `optimizer-worker` services, MWAA + data-trigger
Lambda + DAGs + `data.yml`, MLflow/Unity Catalog model aliases, `genai-gateway` ECS service and the
old `bedrock` module. Modules deleted: `rds`, `elasticache`, `sqs`, `edge`, `mwaa`, `data-trigger`,
`bedrock`. (v3 brought back an RDS instance and a standard SQS queue as new modules `rds`, `run-queue`.)

### 1.3 Where the build differs from the v2 plan (simpler default chosen; Cognito rows no longer apply in v3)

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
| SageMaker endpoint, Studio, Synthetics, Chatbot, AI-log bucket | Not built |
| Cognito advanced security (threat protection) in prod | Not built – AWS threat protection does not apply to federated (Okta) sign-in; risk checks and MFA stay in Okta |
| Lambda publisher "DLQ not empty" alarm, separate SageMaker job alarm | Not needed – no DLQ (sync invoke); job failures fail the state machine (`-failed` alarm) |
| Availability < 99.5 % "business hours" | Hourly alarm over all hours (CloudWatch cannot limit an alarm to business hours) |
| SSM `/mmm/<env>/stepfunctions/{optimization_arn,model_refresh_arn}` | Not built – ARNs go to the API task env (`OPTIMIZATION_STATE_MACHINE_ARN`) and GitHub variables |
| SSM `/mmm/<env>/databricks/job_ids` | Not built – only `databricks/host`; the job id is a Terraform variable used by the model-refresh state machine |
| SSM `/mmm/<env>/sagemaker/model_package_group/<bu>` | Not built – group name is `mmm-<env>-<bu>` (Terraform output `model_package_groups`); image pointers are `/mmm/<env>/images/sagemaker-*` |
| Evaluation states baseline → channel lift → title adjustment | One evaluation Processing job (`evaluate` argument); the three stages are inside the data scientists' code |
| Optimizer reads the approved model from the registry | `model-governance.yml` publishes the approved curves to `models/curves/<bu>/` on approval; the optimizer reads that prefix |

### 1.4 Slide services (`wbd_Presentation.pptx`, still true for `wbd_Presentation_3.pptx` – Okta, RDS, SQS and the dispatcher Lambda are built) vs this repo

Every AWS service on both slides is created by Terraform (data platform and GenAI parts built but
off). **Not created by this repo:** ACM certificate (WBD issues it; `alb_certificate_arn`, expiry
alarm), CloudTrail (WBD organization trail; boundary denies stopping it), IAM Identity Center (WBD
baseline; break-glass alert only), Databricks compute in our VPC (WBD workspace; PrivateLink optional,
off), Bedrock-hosted models (only Bedrock Guardrails; models via API Gateway to OpenAI / Anthropic /
Google – Anthropic via Bedrock is an open question). The repo holds **DevOps code only** – no UI, API,
Databricks or model code.

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
| Sign-in | **Okta OIDC at the ALB** (`authenticate-oidc`, scopes `openid profile email groups`), one Okta OIDC web app per env; client secret in `mmm/<env>/okta/alb-client` read by a Terraform data source (lands in the encrypted state); `okta_sign_in_enabled` switch, 503 until on; MFA in Okta; groups claim `groups` | `docs/04` |
| App DNS | Route 53 alias only if `route53_zone_id` is set; otherwise WBD DNS adds the CNAME from `dns_records_for_wbd` | `docs/01` |
| UI hosting | **`ui` ECS Fargate container** (`/healthz`), image `mmm/ui` | `ecs/dev/ui.json` |
| Database | **RDS PostgreSQL** 16.6 + RDS Proxy (IAM auth, TLS). dev `db.t4g.medium` Single-AZ 50 GiB, staging `db.r6g.large` Multi-AZ 100 GiB, prod `db.r6g.xlarge` Multi-AZ 200 GiB; gp3 + storage autoscaling; PITR 7 / 14 / 35 days; DB snapshot before prod migrations | `infra/modules/rds` |
| Cache / queue | No cache. **Standard SQS run queue + DLQ** (KMS key `sqs`; visibility 360 s, maxReceiveCount 10 → DLQ after ~60 min); dispatcher Lambda keeps running executions ≤ `max_concurrent_runs` (5 / 20 / 50, soft limit, SSM, change applies within a minute); requests older than `max_queue_wait_minutes` (30, allowed 5–50) are dropped with metric `ExpiredRunRequests`; `0` pauses new runs | `run-queue.tf`, `infra/modules/run-queue` |
| Optimization engine | API → SQS → dispatcher → Step Functions (execution name = `run_id`) → SageMaker Processing (`createProcessingJob.sync`) → Lambda publisher (`live` alias) | `optimization.tf` |
| SageMaker image versions | SSM pointer `/mmm/<env_short>/images/sagemaker-*` = `<registry>/<repo>@<digest>`, written by `deploy.yml`; Terraform ignores the value | `optimization.tf`, `deploy.yml` |
| Instance types | `ml.m5.xlarge` (optimizer / evaluation), `ml.m5.2xlarge` (training); no warm pools | `terraform.tfvars` |
| Autoscaling | CPU target tracking 60 % for api and ui (dev 1–2 / 1–2, stg 2–4 / 2–3, prd 3–10 / 2–6) | `ecs.tf` |
| Data orchestration | **No MWAA.** EventBridge Scheduler (per BU) + on-demand `mmm.refresh` event → Step Functions HTTP Task → Databricks Jobs API via an **EventBridge connection** (OAuth) | `data.tf` |
| Model registry | **SageMaker Model Registry** per BU (`<prefix>-<bu>`); eval role can only reject; approve role (GitHub Environment `<env>-model-promotion`) approves, publishes curves to `models/curves/<bu>/` and the drift baseline to `models/baseline/<bu>/`, and writes `approval.json` next to `evaluation.json`; rollback re-approves the previous version (curves + baseline) | `docs/10` §7 |
| Write-back | After `RegisterModel`, the model-refresh state machine runs the Databricks write-back job (`databricks_writeback_job_id`; parameters business_unit, refresh_id, results_uri, model_package_arn); failure → `WritebackFailed`, the registered model stays | `data.tf`, `data/README.md` |
| Drift monitor | `mmm-<env>-model-monitor`: export (refresh job, `purpose=monitor`) → `CheckDrift` (training image, writes `drift.json` `{"score":0-1,"checks":{}}`) → metric `MMM/Models ModelDrift` → alarm `<prefix>-model-drift-<bu>`; threshold `drift.threshold` (0.2) in `data/model-thresholds.yaml`; daily schedule `mmm-<env_short>-drift-<bu>`, off until the first baseline; `auto_refresh_on_drift = false` (alert only) | `data.tf`, `docs/10` §3b |
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
   the user verifies → only then implement. ("Don't add any code unless I verify.") The user wants
   the project complete *before* the client values arrive – placeholders + defaults, everything else done.
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

Mock-plan results on 6 Nov 2026, v3 (resources to add):

| Env | Default | All optional features on |
|---|---|---|
| dev | 311 | 459 |
| staging | 326 | 476 |
| prod | 326 | 478 |

Last run (6 Nov 2026, v3): all of the above clean – 24 modules validate, tflint 0, Checkov 1323
passed / 0 failed (accepted findings have a `#checkov:skip=<ID>:<reason>` comment), actionlint 0,
shellcheck 0, secret scan clean, `python scripts\model_governance.py --thresholds data\model-thresholds.yaml check-thresholds` OK.

---

## 5. What is built

| Area | Content |
|---|---|
| Bootstrap | `infra/bootstrap`: state bucket (versioned, KMS, TLS-only), KMS key |
| Modules (`infra/modules`, 24) | kms, permission-boundary, iam-oidc, budgets, network, secrets, ecr, s3-bucket, log-bucket, **rds**, ecs-cluster, alb, ecs-service, waf-regional, step-functions, **run-queue**, sagemaker, lambda-function, monitoring, log-shipping, backup, databricks-access, bedrock-guardrails, llm-gateway (bold = new in v3). Each has a README |
| Stack files (`infra/environments/<env>`) | `main.tf` (KMS, IAM/OIDC, network, secrets, ECR, buckets, RDS), `frontdoor.tf` (Okta OIDC on the ALB, ALB, WAF, Route 53), `ecs.tf` (api, ui, migrate, platform-check), `optimization.tf` (SSM image pointers, SageMaker role, publisher Lambda, optimization state machine), `run-queue.tf` (run queue, dispatcher, SSM run limit), `data.tf` (Databricks access + connection, training side, model-refresh state machine with write-back, model-monitor state machine, refresh + drift schedules, on-demand rule), `genai.tf`, `monitoring.tf`, `backup.tf`, `outputs.tf`, `variables.tf`, `tests/mock-plan.tftest.hcl` |
| ECS templates | `ecs/<env>/api.json`, `ui.json`, `migrate.json` |
| Workflows | `api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `publisher-ci` (via `_python-service-ci`; skip while the app folder is absent), `deploy` (api, ui, optimizer, training, publisher; promotion, prod RDS snapshot (`DB_INSTANCE_ID`), migration, smoke (Okta redirect when `SMOKE_CHECK_LOGIN`), optimization dry run through the run queue in dev/staging, rollback of ECS + SSM pointers + Lambda alias; deploys only when the CI run's test job succeeded), `terraform` (+ `_terraform-apply`, drift skip when no role; also on `data/model-thresholds.yaml`), `databricks`, `model-governance` (curves + baseline + `approval.json`), `repo-checks`. **All actions pinned to commit SHAs** (`@<sha> # vX.Y.Z`; Dependabot updates them) |
| Monitoring | Alarms: API 5xx, availability (hourly 99.5 %), UI/API healthy targets, RDS CPU / free storage / connections / read + write latency, run queue (`runs-oldest-request`, `runs-dlq-not-empty`, `runs-dispatcher-errors`, `runs-dispatcher-throttles`, `runs-expired-requests`), `model-drift-<bu>`, `model-monitor-failed`, what-if p95, optimization runtime max 10 min + standard p95 2 min (app metric), state machines failed + throttled, Lambda errors, cert expiry, model refresh overdue (7 days), LLM gateway 4xx / 5xx / latency, guardrail interventions, GenAI token quota 80 % per BU. Dashboards: platform, api-ui, optimization (+ run queue), rds, cost (+ training with drift, genai). Events: ECS deploy failed / service error, GuardDuty High, break-glass, backup job failed, model package state |
| Backup | RDS instance (native PITR + AWS Backup) + `results`, `approved-worm`, `models`, and with the data platform `training-data`, `lakehouse` (lakehouse cost to confirm) |
| Scripts | `smoke.sh` (health + Okta redirect when `SMOKE_CHECK_LOGIN`), `dry-run-optimization.sh` (post-release dry run sent to the run queue), `deploy-components.sh`, `lambda-release.sh`, `trigger-model-refresh.sh`, `platform-check.sh` (queue, RDS Proxy), `model_governance.py` (SageMaker registry, thresholds incl. `drift`, baseline, `approval.json`), `promote-images.sh`, `ecs-deploy.sh`, `run-migration.sh`, `db-bootstrap.py`, `setup-github.ps1` (`-DatabricksClientId`), `sync-environments.ps1`, `mock-plan.ps1`, `validate-modules.ps1`, `checkov-scan.ps1`, `secret-scan.ps1` |
| Docs | `docs/00`–`13` and `docs/runbooks/` (deploy, rollback, scaling, optimization run failed incl. DLQ redrive, model refresh failed, write-back failed, model drift, Okta outage, DB restore (RDS), ECS task stuck, rotation incl. Okta secret, pipeline failure, model rollback, GenAI, security incident, break-glass); `data/README.md` = evaluation, write-back and monitor contracts |
| Requirement doc tools | `docs/requirements/tools/` – `extract_pptx.py` (slide text + images), `extract.py` (v1 docx/xlsx dump), `build_v3.py` (generates the `_3` xlsx/docx; `build_v2.py` / `check_v2.py` for v2), `build_client_questions.py` (generates `devops_3_client_question.xlsx`); README explains use |

v1 defects D1–D4 are fixed: Trivy `version:` on every trivy-action, drift job skips without role,
skopeo installed in `deploy.yml`, `github_org`/`github_repo` = `Yashwanth-wbd`/`wbd-aws-devops`.

---

## 6. Open issues and gaps

### 6.1 Open questions for WBD (implemented with the simpler industry-standard default)

| # | Question | Default implemented |
|---|---|---|
| Q1 | ALB reachable from the internet or only WBD ranges? Shield Advanced? | Internet + WAF + Okta sign-in; `alb_ingress_cidrs` to restrict; no Shield Advanced |
| Q2 | Optimization runs at the same time; fairness between BUs; queue wait | Run queue, soft limit 5 / 20 / 50, order of arrival, 30 min wait; per-user limits app side |
| Q3 | External LLM providers = data leaves AWS | Behind `enable_genai` + guardrail PII masking/blocking; needs written WBD approval |
| Q4 | Databricks workspace IP access list must allow Step Functions HTTP calls | Confirm with WBD Databricks |
| Q5 | Okta: OIDC app per env, issuer, group names, logout with `client_id` | `groups` claim; names `mmm-bu-*` / `mmm-role-*` (docs/04, 06); Okta logout URL with `client_id` (to confirm) |
| Q6 | Separate Databricks service principal for bundle deploy (`DATABRICKS_CLIENT_ID`) vs the refresh SP | Two SPs recommended |
| Q7 | Okta client secret in the encrypted Terraform state | Accepted; read from Secrets Manager, state bucket KMS + restricted |
| Q8 | RDS sizes, Multi-AZ, read replica | As in section 2; no read replica; resize after the load test |
| Q9 | Write-back scope (every version or only approved) and Gold tables | Every registered version keyed by `refresh_id` + version, approval status from `approval.json`; `gold.<bu>_model_results` |
| Q10 | Drift definition, threshold, schedule, auto-retrain | Score 0–1, threshold 0.2, daily, alert only |

### 6.2 Gaps (still open)

CODEOWNERS (needs team names), DAST (ZAP), SBOM (Syft), image signing (cosign), dev cost
scale-down, performance tests, post-deploy integration tests beyond the dry run, Synthetics canary,
business-continuity page, shared account decision.

App contract added on 5 Nov 2026 (the app teams must implement): `DRY_RUN` env in the optimizer
image and `dry_run` in the publisher event; metrics `OptimizeDurationMs` (`RunSize` standard/large,
from the publisher) and `GenAITokens` (`BusinessUnit`, from the API) – see `infra/modules/monitoring/README.md`.
Added in v3: the API sends run requests to `OPTIMIZATION_QUEUE_URL` (message contract in
`infra/modules/run-queue/README.md`) and validates Okta tokens against `OKTA_ISSUER`; the training image
writes `baseline/`, `predictions/`, `lift/` and has a `drift` entrypoint; the Databricks bundle has the
write-back job and the `purpose=monitor` export – contracts in `data/README.md`.

### 6.3 Not in this repo but needed before a real deployment works

- App code: `apps/api`, `apps/ui`, `apps/sagemaker-optimizer`, `apps/sagemaker-training`,
  `apps/results-publisher`, and the Databricks bundle `data/databricks/`. Until then the CI jobs
  skip and there is nothing to deploy.
- Real values (section 7), issued ACM certificate, WBD DNS record, Okta OIDC apps (client ID + secret).
- Dependabot PRs open: #1 (10 GitHub Actions updates), #2 (2 Python updates in `scripts/`) – merge when green.

### 6.4 How the app teams plug in (same repo, own folders)

| Team | Folder | Pipeline | Must provide |
|---|---|---|---|
| Frontend | `apps/ui` | `ui-ci.yml` | Dockerfile (nginx, non-root), `/healthz` |
| Backend (API, LangGraph, QA dashboard) | `apps/api` | `api-ci.yml` | Dockerfile, `/api/health`, Alembic migrations, PostgreSQL RLS per BU, run row `QUEUED` + SQS message to the run queue, Okta token check (`OKTA_ISSUER`, ALB `x-amzn-oidc-data`), `GenAITokens` metric |
| Data science – optimizer | `apps/sagemaker-optimizer` | `optimizer-ci.yml` | Processing image: reads `runs/<run_id>/input/` + `curves/<bu>/`, writes `runs/<run_id>/`, honours `DRY_RUN` |
| Data science – training / evaluation | `apps/sagemaker-training` | `training-ci.yml` | Training image + `evaluate` argument writing `evaluation.json`, `curves/`, `baseline/`, `predictions/`, `lift/`; `drift` entrypoint writing `drift.json`; real limits in `data/model-thresholds.yaml` |
| Results publisher | `apps/results-publisher` | `publisher-ci.yml` | Lambda writing to RDS PostgreSQL (via RDS Proxy), honours `dry_run`, `OptimizeDurationMs` with `RunSize` |
| Data engineering | `data/databricks/` | `databricks.yml` | Asset Bundle (Lakeflow Bronze → Gold, feature export) writing Parquet + metadata to `training-data/<bu>/<refresh_id>/`; `purpose=monitor` export to `lakehouse/monitoring/<bu>/<date>/`; write-back job into Gold |

DevOps owns `infra/`, `ecs/`, `.github/`, `scripts/`, `docs/` (protect with CODEOWNERS once team names
are known). DevOps to-do with the teams: starter Dockerfile skeletons with health checks, dev access
(read-only permission set, logs, ECS Exec in dev), seed curves for the dry run, weekly cross-team sync
(env changes, quotas, cost), releases (main → dev, `-rc` → staging, `vX.Y.Z` → prod), model approvals,
runbooks / KT to WBD (Release 1 in 8 weeks, Release 2 and handover by week 16 – `wbd_final.docx`).

### 6.5 Working without AWS admin access (WBD VDI)

No admin and no access keys – IAM Identity Center (Okta + MFA) short-lived credentials, GitHub
Actions does the applies, WBD teams do the one-time admin steps. Details: `docs/02`, `docs/03`.

**Ask WBD Cloud Platform for (Okta group → permission set):** `DevOps` in dev and staging (scoped to
`mmm-*`, no Identity Center / Organizations / CloudTrail changes), prod read-only + time-limited
elevation per change ticket; `ReadOnly` everywhere; `SecurityAudit` in prod.

| Task | How without admin |
|---|---|
| AWS CLI login | `aws configure sso`, `aws sso login --profile wbd-mmm-dev` (temporary credentials) |
| Terraform | `fmt` / `validate` locally (no AWS); `plan` locally with `DevOps`; `apply` only by GitHub Actions (`gha-apply`), approvals in GitHub Environments |
| Bootstrap + GitHub OIDC provider + `gha-*` roles (needs IAM create) | Once per account: WBD Cloud runs `infra/bootstrap` + first apply, or gives time-limited elevation under a change ticket; afterwards the permission boundary limits the roles to `mmm-*` |
| Secret values | Not needed – RDS-managed DB password, apps read via task roles, owners fill their own secrets; ask for `PutSecretValue` on `mmm/<env>/*`, `GetSecretValue` in dev only |
| App URL / DNS / certificate | Output `dns_records_for_wbd` → WBD DNS team; ACM certificate issued by WBD, ARN into tfvars |
| Okta OIDC app | Output `okta_app_settings` → WBD Identity team → issuer + client ID (tfvars); they or DevOps put the client secret in `mmm/<env>/okta/alb-client` |
| Quotas, GuardDuty / CloudTrail / Config, Databricks admin, GitHub repo admin | Quota request (WBD Cloud approves); account baseline; WBD Databricks admins; repo admin for `setup-github.ps1` |
| External URLs (LLM providers, Splunk, Databricks) | Egress via NAT, allow-list / proxy by WBD network team; on the VDI set `NODE_EXTRA_CA_CERTS` / `REQUESTS_CA_BUNDLE` |
| Service-to-service access | Already in code: per-service IAM roles (API task, SageMaker, Step Functions, publisher) |

**Fallbacks if access is even smaller:** pipeline only (`ReadOnly` + PRs, GitHub Actions plans and
applies – preferred by security teams); a sandbox account; just-in-time elevation (e.g. AWS TEAM);
WBD runs the bootstrap while DevOps guides on a shared screen. One access request to WBD covering
all of the above – most items are already in `docs/01-client-inputs-tracker.md`.

---

## 7. Values to collect from the client and where they go

**Send to WBD:** `docs/requirements/devops_3_client_question.xlsx` – 49 inputs only WBD can provide
(accounts and access, network, domain / certificate / Okta OIDC, GitHub and approvals, operations incl.
RDS sizing and run limits, Databricks and data incl. write-back job and drift, GenAI) with dev /
staging / prod columns, plus sheet `decisions_to_confirm` (Q1–Q10, lakehouse backup cost, shared
account). Generated by `docs/requirements/tools/build_client_questions.py`; once WBD fills it in,
edit the workbook directly. Things DevOps creates (state bucket, KMS, roles, buckets, queue) are not in it.

Full list with owners: `docs/01-client-inputs-tracker.md`. Find every placeholder:
`git grep -n -A1 "add actual value"`. Edit each environment's `terraform.tfvars` separately.

| Area | tfvars / place |
|---|---|
| Accounts, region | `aws_account_id`, `aws_region`, `allowed_regions`, `dr_region`, `backend.tf`, `infra/bootstrap/<env>.tfvars` |
| Network | `vpc_cidr`, `availability_zone_ids`, `enable_nat_gateway`, TGW / resolver values |
| Front door | `app_domain_name`, `alb_certificate_arn` (workload region, ISSUED), `alb_ingress_cidrs`, `route53_zone_id` (optional), `geo_allow_countries`, `waf_count_only` |
| Sign-in | `okta_issuer`, `okta_client_id` (one Okta OIDC app per env; give WBD Okta `terraform output okta_app_settings`), `session_hours`; secret `mmm/<env>/okta/alb-client`, then `okta_sign_in_enabled = true` and re-run `setup-github.ps1` |
| Database | `rds_instance_class`, `rds_allocated_storage`, `rds_max_allocated_storage`, `rds_multi_az` (`rds_engine_version`) |
| Optimization | `optimizer_instance_type`, `optimizer_max_runtime_seconds`, `max_concurrent_runs`, `max_queue_wait_minutes` |
| Data platform | `databricks_host`, `databricks_account_id`, `databricks_privatelink_service_name`, `databricks_sp_client_id`, `databricks_refresh_job_id`, `databricks_writeback_job_id`, `training_instance_type`, `model_refresh_schedule` / `_timezone`, `enable_model_refresh_schedule`, `model_monitor_schedule`, `enable_model_monitor_schedule` (after the first approval), `model_drift_threshold`, `auto_refresh_on_drift`, `training_data_retention_days`, `data/model-thresholds.yaml` (incl. `drift.threshold`), then `enable_data_platform = true` (UC role two-phase) |
| GenAI | `llm_providers`, `genai_token_quotas`, `genai_reserved_concurrency`, guardrail thresholds, `manage_apigw_account_logging_role`, then `enable_genai = true` |
| Monitoring, budgets, backup | `alert_emails`, `budget_alert_emails`, `monthly_budget_usd`, `splunk_hec_endpoint`, `approved_worm_lock_mode` (irreversible for COMPLIANCE), `approved_worm_retention_days`, prod `enable_vault_lock` / `enable_cross_region_copy` |
| GitHub | reviewer teams/users, model approvers, `-DatabricksClientId`, change-ticket pattern |

---

## 8. Secrets (never in Git – filled in AWS after the first apply)

| Secret / credential | Filled by | When |
|---|---|---|
| RDS admin password | RDS-managed, auto-rotated | automatic |
| `mmm/<env>/okta/alb-client` (`{"client_secret": "..."}`) | WBD Identity or DevOps (never by email) | before `okta_sign_in_enabled = true`; rotation in `docs/runbooks/rotation.md` |
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
  ECS_CLUSTER, APP_URL, APP_SUBNET_IDS, DATA_CLIENTS_SG_ID, DB_INSTANCE_ID, PUBLISHER_FUNCTION,
  OPTIMIZATION_STATE_MACHINE_ARN, OPTIMIZATION_QUEUE_URL, SMOKE_CHECK_LOGIN, SAGEMAKER_IMAGE_PARAM_PREFIX`
  (+ `MODEL_REFRESH_STATE_MACHINE_ARN`, `DATABRICKS_HOST` with the data platform; `DATABRICKS_CLIENT_ID`
  via `-DatabricksClientId`); dev/staging also `RESULTS_BUCKET, MODELS_BUCKET, DRY_RUN_BUSINESS_UNIT`
  (dry run); staging/prod also `SOURCE_ECR_READ_ROLE_ARN, SOURCE_ECR_REGISTRY`. Optional
  `SMOKE_BASE_URL`, `SMOKE_DRY_RUN`, `CHANGE_TICKET_PATTERN`. `SMOKE_CHECK_LOGIN` follows
  `okta_sign_in_enabled` – re-run `setup-github.ps1` after turning sign-in on.
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
| Mock plan | Takes ~5–12 min; run it in the background **in-process** (`& .\scripts\mock-plan.ps1 -Environment dev,staging,prod`) – `powershell -File ... -Environment dev,staging,prod` passes one string and fails the ValidateSet. The script sets `$ErrorActionPreference = 'Continue'` around terraform (Windows PowerShell 5.1 otherwise stops on the first stderr line). The all-features run catches type errors that `validate` misses (e.g. a conditional returning a tuple or `[]`: use `try(map[key], [])`) |
| PowerShell bulk edits | Inside `@( ... )`, `'a' + "`n" + 'b'` is split by the comma operator and silently drops text. Use the editor's replace tool, or one double-quoted string with `` `n ``; check with `git --no-pager diff -U0` |
| Deleting folders | Recursive delete on the share: a single `-LiteralPath`, or `git rm -r` then `git reset` to keep it unstaged |
| Robocopy mirror | The auto-review asks for approval for `robocopy /MIR` to `C:\work\wbd` – approve it in the card (it is the scratch copy) |
| Checkov | Accepted findings get `#checkov:skip=<ID>:<reason>` inside the resource (same style as existing ones) |
| Shellcheck | Local files have CRLF: strip `\r` into a temp copy first, otherwise every line reports SC1017. CI checks the LF version in Git |
| Line endings | `.gitattributes` normalizes; CRLF/LF warnings on `git add` are expected |
| Executable bit | New `.sh` files: `git update-index --chmod=+x scripts/<file>.sh` |
| git push | Git cannot prompt for a password here. Push with the `gh` login: `git -c credential.helper= -c "credential.helper=!gh auth git-credential" push origin main` |
| Push approval | The agent's auto-review blocks pushes to `main`; the user approves the push in the approval card |
| App CI | Editing a workflow file triggers its CI; app CIs skip while `apps/<name>` is absent and `deploy.yml` then skips too |
| Requirement docs | xlsx/docx are generated, not hand-edited: edit `docs/requirements/tools/build_v3.py` and re-run it (`uv run --no-project --with openpyxl --with python-docx python build_v3.py <docs/requirements>`) |
| model_governance.py | Global option before the command: `python scripts\model_governance.py --thresholds data\model-thresholds.yaml check-thresholds` |
| Slides as images | Client decks are mostly images: `extract_pptx.py` saves them; read the images to see the diagrams |
| Python helpers | `uv run --no-project --with <pkg> python <script>` – no installs needed |

---

## 11. Next steps

### 11.0 Right now (after session 19)

1. **Commit and push v3 when the user asks** (one commit is fine: "v3: Okta OIDC, RDS PostgreSQL, run
   queue, write-back, drift monitor"); new `.sh` files: none in v3. Then watch the push workflows
   (terraform plan matrix, repo-checks, actionlint) and fix anything red.
2. Send `devops_3_client_question.xlsx` to WBD.

### 11.1 Process for the next requirement (requirement 4)

1. **Read the new document** (`docs/requirements/tools/extract_pptx.py` for slides, read the images).
2. **Compare with what is built** (sections 1–5 of this file, `infra/modules/README.md`): replacement
   map removed / replaced / new / kept.
3. **Write the plan files** `docs/requirements/devops_plan_4.txt`, `PROJECT_CONTEXT_4.md` and generate
   `aws_resource_list_4.xlsx` + `wbd_mmm_ecs_final_4.docx` (copy `tools/build_v3.py` → `build_v4.py`).
   Mark open points `[ASK]`, assumptions `[ASM]`. **Stop for the user's verification.**
4. **Implement**: new/changed modules (each with a README) → dev stack (`infra/environments/dev`,
   `ecs/dev`) → `sync-environments.ps1` → workflows, scripts, docs, runbooks. Delete what is unused.
5. **Validate** (section 4.3), update the expected mock-plan counts.
6. **Update** the `_4` files with what was built (status, decisions, differences), the client
   question workbook, and this file.
7. **Push when asked**, then check the GitHub Actions runs and fix anything red.

### 11.2 Order of work once the client values arrive

1. Fill dev values (section 7) – `terraform.tfvars`, `infra/bootstrap/dev.tfvars`, `backend.tf`.
2. `aws configure sso` for dev (`docs/02`); `aws sts get-caller-identity`.
3. Bootstrap state; copy bucket and `state_kms_key_arn` into `backend.tf` / tfvars.
4. ACM certificate ISSUED in the workload region; Okta issuer + client ID from WBD.
5. First apply of dev from the laptop (sign-in off: the ALB answers 503). Confirm the SNS email subscriptions.
6. Give WBD DNS `dns_records_for_wbd` and WBD Okta `okta_app_settings`; client secret into
   `mmm/<env>/okta/alb-client`; `okta_sign_in_enabled = true`; apply.
7. `setup-github.ps1` for dev → Terraform runs from GitHub Actions from now on.
8. DB bootstrap (section 8).
9. When the app teams merge `apps/*`: CI builds `sha-<7>` → `deploy.yml` deploys to dev.
10. Run the "Validate" sections in `infra/environments/dev/README.md`.
11. Staging (tag `vX.Y.Z-rcN`), then prod (tag `vX.Y.Z` with change ticket).
12. Data platform values → `enable_data_platform = true` → validate (`docs/10`); after the first
    approved model per BU (baseline published) → `enable_model_monitor_schedule = true`.
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
| 12 | 5 Nov 2026 | Review the whole project against requirement 2 (no code), then "fix all" | Built the missing plan items: Step 9 alarms + 7 dashboards, backup of training-data/lakehouse, deploy dry run, actions pinned to SHAs; Cognito threat protection recorded as not applicable; doc fixes (docs/08, 09, 11, 13, runbooks README, module READMEs, xlsx cells); offline validation passed; pushed to `main` (`d52c7cf`), all workflows green |
| 13 | 5 Nov 2026 | Confirm code, docs and this file are pushed | Local = `origin/main`, nothing uncommitted; Dependabot PRs for the pinned actions may be open – review and merge |
| 14 | 5 Nov 2026 | Check the `_2` xlsx / plan / docx; second full review; slide-by-slide service check; DevOps-only confirmation; how to work with the app teams | `devops_plan_2.txt` status note (`1c92341`); sections 1.3 (3 SSM differences, evaluation, curves), 1.4 and 6.4 added; `PROJECT_CONTEXT_2.md` 4a updated; all pushed (`87f3b2f`) |
| 15 | 5 Nov 2026 | Chat lost on reinstall? Which approach (v1 or v2)? How to work without AWS admin on the VDI | Chat history is local to the machine – continue by attaching this file; recommended v2 (client deck, managed services); section 6.5 (access without admin) added and pushed (`29ee523`); Office lock files ignored (`35b8a47`) |
| 16 | 5 Nov 2026 | Full project re-read; refresh this file's header | "Last updated" and key commits in section 1 updated and pushed (`ed26c99`) |
| 17 | 5 Nov 2026 | What must the client provide before starting (only client-owned values), as an Excel | `docs/requirements/devops_2_client_question.xlsx` (44 inputs + 8 decisions) and its generator; section 7 and `docs/01` point to it; `docs/01` pinning row fixed; pushed |
| 18 | 6 Nov 2026 | Full walkthrough (no code); new requirement `wbd_Presentation_3.pptx` – plan and architecture only | `devops_plan_3.txt`, `PROJECT_CONTEXT_3.md`, `aws_resource_list_3.xlsx`, `wbd_mmm_ecs_final_3.docx`, `tools/build_v3.py` |
| 19 | 6 Nov 2026 | Implement requirement 3 (remove what is not needed, add new services, pipelines too) so the project is ready before the client values arrive | v3 implemented (sections 1.1, 1.2, 2, 5): Cognito + Aurora removed; Okta OIDC at the ALB, `rds`, `run-queue`, write-back, model monitor + drift alarms, governance baseline + `approval.json`; `deploy.yml`, `terraform.yml`, `model-governance.yml`, smoke / dry run / platform check; docs 00–13, runbooks (3 new), `data/README.md`; bugs found and fixed by the mock plan (dashboard conditional) and in `mock-plan.ps1` (stderr); all offline checks clean; `_3` files updated + `devops_3_client_question.xlsx`. **Not committed** |

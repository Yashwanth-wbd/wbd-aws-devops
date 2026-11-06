# WBD MMM DevOps – Project Context v3 (updated client architecture)

Companion to `PROJECT_CONTEXT_2.md`. v2 (from `wbd_Presentation.pptx`) is **built** in this repo and
pushed to `main`. This file describes the **v3 target** from the updated client deck
`wbd_Presentation_3.pptx` and what has to change in the code to get there.

Status (6 Nov 2026): **implemented with placeholder values and validated offline** (mock plan:
dev 311 / 459, staging 326 / 476, prod 326 / 478 resources to add, default / all features on).
Nothing applied to AWS; not committed yet. Where the build differs from this plan: section 4a.

---

## 0. How to resume in a new chat

> I'm continuing the WBD MMM DevOps project, v3 architecture. Read `Project_memory.md` (root) and
> `docs/requirements/PROJECT_CONTEXT_3.md` first, then `docs/requirements/devops_plan_3.txt`. The
> project is at `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`
> (GitHub `Yashwanth-wbd/wbd-aws-devops`). Follow the rules in section 3 of `Project_memory.md`.
> Today I want to: <e.g. "implement v3 Step 6 (RDS PostgreSQL)">.

---

## 1. Documents

| File (`docs/requirements/`) | What it is |
|---|---|
| `wbd_Presentation_3.pptx` | **Client v3 architecture** – slide 1 "supports auto ML activities", slide 2 "supports optimization and explainable planning" (both slides are images; read them with `tools/extract_pptx.py`) |
| `devops_plan_3.txt` | v3 step-by-step build prompt (Steps 0–16); section A = change summary vs v2; **(v3)** marks every step that changes the built code |
| `aws_resource_list_3.xlsx` | v3 resources in creation order, sheets dev/staging/prod; column "Change vs v2" (Same/Changed/New; yellow = new, green = changed, grey = not built / owned by WBD) and "Repo today (v2 build) → v3 action"; sheets `removed_vs_v2` and `decisions` (proposed defaults) |
| `wbd_mmm_ecs_final_3.docx` | v3 design document (what changed, target platform, flows, environments, stages 0–17, questions with the proposed default, impact on the code, risks) |
| `tools/build_v3.py` | Generates the `_3` xlsx and docx (edit `ROWS` / `REMOVED` / `STATUS` / `DECISIONS`, re-run) |
| `*_2.*`, `wbd_Presentation.pptx` | v2 inputs (what the current code implements) |

---

## 2. v3 architecture in one page

**Slide 1 – auto ML activities (Hybrid Lakehouse + MLOps, auto-refresh, app-triggered refresh):**
unchanged pipeline – EventBridge → Step Functions → Databricks Lakeflow Jobs (ingestion → Bronze →
Silver → Gold per-BU modeling tables with adstock & saturation → Feature Export) → immutable Parquet +
metadata in S3 → SageMaker training → evaluation (baseline → channel lift → title adjustment) → model
registration → SageMaker Registry + S3. **New:** (a) "**Model predictions, lift & evaluation results
written back to corresponding data**" – a two-way arrow between Step Functions and the Gold layer;
(b) the registry box now reads "stores approved models and response curves **+ model drift
monitoring**".

**Slide 2 – optimization and explainable planning (50–150 concurrent planners):** Planner → DNS/WAF →
ALB → ECS UI → ECS API (FastAPI + LangGraph tools + QA dashboard). **New:** (a) "**SSO / Authentication
– Okta** (Enterprise Identity Provider)" replaces Cognito; (b) **RDS PostgreSQL** (plans, runs,
allocations) replaces Aurora PostgreSQL; (c) **API → SQS → Lambda "message dispatcher" → Step
Functions (async)** replaces the direct API → Step Functions call. Unchanged: SageMaker job for
optimization & decision (Model Summarizer · Optimizer · Simulation) with SageMaker Registry + approved
response curves in S3 → S3 outputs → Lambda results publisher → database; API Gateway → OpenAI /
Anthropic / Google + Bedrock Guardrails; ECR; Route 53 · WAF · ACM.

Control plane, security + network and operations bands are unchanged on both slides.

---

## 3. Service replacement map (v2 built → v3)

| v2 (built) | v3 | Type |
|---|---|---|
| Cognito user pool + SAML IdP (Okta) + app client + hosted domain; ALB `authenticate-cognito` | WBD Okta OIDC app per env; ALB `authenticate-oidc` (client secret in Secrets Manager) | Replaced |
| SSM `cognito/user_pool_id`, `cognito/client_id`; API env `COGNITO_*` | SSM `okta/issuer`; API env `OKTA_ISSUER` | Replaced |
| Aurora PostgreSQL Serverless v2 cluster (+ RDS Proxy) | RDS for PostgreSQL DB instance, Multi-AZ in stg/prd (+ RDS Proxy) | Replaced |
| Aurora alarms (CPU, ACU, connections, free local storage, replica lag); dashboard `aurora` | RDS alarms (CPU, free storage, connections, read/write latency, replica lag if a replica); dashboard `rds` | Replaced |
| Aurora cluster snapshot before prod migration (`deploy.yml`) | RDS DB snapshot (`create-db-snapshot`) | Replaced |
| API task role `states:StartExecution` | API `sqs:SendMessage` → SQS run queue (+ DLQ) → dispatcher Lambda `states:StartExecution` with a concurrency gate | Replaced |
| – | KMS key `sqs`, VPC endpoint `sqs`, SSM `optimization/max_concurrent_runs`, queue / DLQ / dispatcher alarms | New |
| Evaluation results only in `models/evaluation/<bu>/<refresh_id>/` | + write-back states in `model-refresh` → Databricks write-back job → Gold tables | New |
| – | `model-monitor` state machine + Scheduler per BU → drift Processing job → `ModelDrift` metric + alarm (optional auto-refresh) | New |
| Everything else (ECR, ECS ui/api/migrate, ALB, WAF, ACM, DNS, optimization state machine, SageMaker jobs, publisher Lambda, S3 buckets, model-refresh state machine, registry + governance, Databricks access, GenAI, monitoring, backup, CI/CD) | same | Kept |

---

## 4. Impact on the current code (module by module)

| Path | v3 action |
|---|---|
| `modules/cognito` | **remove** |
| `modules/aurora` | **replace** with `modules/rds` (DB instance, parameter group, subnet group, Enhanced Monitoring role, RDS Proxy + its role; start from the v1 `rds` module in git history and keep the v2 proxy / IAM-auth settings) |
| new `modules/sqs` | queue + DLQ + KMS + queue policy (v1 module in git history as a starting point; Standard instead of FIFO) |
| new `modules/run-dispatcher` | dispatcher Lambda code + SQS event source mapping (DevOps-owned plumbing like `llm-gateway/lambda`) – or reuse `lambda-function` with a code path [ASM] |
| `modules/alb` | `authenticate-oidc` (Okta) instead of `authenticate-cognito`; `/api/*` deny-unauthenticated unchanged |
| `modules/network` | `sqs` interface endpoint; `aurora` SG → `rds`; dispatcher uses the `lambda` SG |
| `modules/kms` | purpose `sqs` |
| `modules/monitoring` | RDS alarms, queue / DLQ / dispatcher alarms, drift alarm, model-monitor failed; dashboards `rds`, optimization (+ queue), training (+ write-back, drift) |
| `modules/backup` | RDS DB instance in the selection |
| `modules/databricks-access` | read `models/evaluation/*`, write `lakehouse/monitoring/*` |
| `environments/*/frontdoor.tf` | Okta OIDC on the ALB; remove Cognito; `okta_app_settings` = OIDC values |
| `environments/*/main.tf` | `rds` instead of `aurora`; secret `okta/alb-client`; SSM `optimization/max_concurrent_runs`, `okta/issuer`; remove `cognito/*` |
| `environments/*/ecs.tf` | API task role `sqs:SendMessage`; env `OPTIMIZATION_QUEUE_URL`, `OKTA_ISSUER`; remove `COGNITO_*`; UI `LOGOUT_URL` → Okta |
| `environments/*/optimization.tf` | SQS queue + DLQ + dispatcher Lambda in front of the optimization state machine |
| `environments/*/data.tf` | write-back states after `RegisterModel`; `model-monitor` state machine, schedules, role |
| `environments/*/variables.tf`, `terraform.tfvars` | remove `okta_saml_metadata_url`, `cognito_domain_prefix`, `aurora_*`; add `okta_issuer`, `okta_client_id`, `okta_client_secret_name`, `rds_instance_class`, `rds_allocated_storage`, `rds_max_allocated_storage`, `rds_multi_az`, `rds_engine_version`, `max_concurrent_runs`, `max_queue_wait_minutes`, `databricks_writeback_job_id`, `model_monitor_schedule`, `enable_model_monitor_schedule`, `model_drift_threshold`, `auto_refresh_on_drift` (each with `# add actual value` where WBD supplies it) |
| `environments/*/outputs.tf` | `github_environment_variables`: `DB_INSTANCE_ID`, `OPTIMIZATION_QUEUE_URL` (drop `AURORA_CLUSTER_ID`) |
| `environments/*/tests/mock-plan.tftest.hcl` | new expected counts |
| `ecs/<env>/api.json`, `ui.json` | env names (queue URL, Okta issuer; no Cognito IDs) |
| `.github/workflows/deploy.yml` | RDS snapshot; dry run through the queue; Okta smoke |
| `.github/workflows/model-governance.yml`, `scripts/model_governance.py` | publish `models/baseline/<bu>/` on approve/rollback; write `approval.json` |
| `scripts/` | `dry-run-optimization.sh` (send to SQS, wait for the execution), `platform-check.sh` (SQS, RDS), `smoke.sh` (Okta redirect), `setup-github.ps1` (new variables) |
| `data/model-thresholds.yaml`, `data/README.md` | `drift:` section; write-back + drift + evaluation output contract (`predictions/`, `lift/`, `manifest.json`) |
| `docs/` | 01, 04 (Okta OIDC), 05, 06, 08 (RDS), 09, 10 (write-back, drift), 11; runbooks `okta-outage` (replaces `cognito-idp-outage`), `db-restore`, `optimization-run-failed`, `scale-planning-season`, `rotation`, new `model-drift`, `write-back-failed` |
| `docs/requirements/devops_2_client_question.xlsx` | v3 needs a `devops_3_client_question.xlsx` (Okta OIDC, RDS sizing, max concurrent runs, write-back tables, drift definition) |
| Unchanged | bootstrap, permission-boundary, iam-oidc (only RDS snapshot actions), budgets, secrets module, ecr, s3-bucket, log-bucket, ecs-cluster, ecs-service, waf-regional, step-functions, sagemaker, lambda-function, log-shipping, bedrock-guardrails, llm-gateway; workflows api/ui/optimizer/training/publisher-ci, terraform, databricks, repo-checks |

### 4a. Where the build differs from the table above (implemented 6 Nov 2026)

| Plan | Built |
|---|---|
| New `modules/sqs` + `modules/run-dispatcher`; queue in `optimization.tf` | One **`modules/run-queue`** (queue, DLQ, dispatcher Lambda with its code, event source mapping, `runs-*` alarms), called from a new stack file **`run-queue.tf`** |
| Variable `okta_client_secret_name` | Fixed secret name `mmm/<env>/okta/alb-client`; new switch **`okta_sign_in_enabled`** (default `false`: ALB answers 503 until the secret holds `{"client_secret": ...}`) |
| Drift check weekly | **Daily** `cron(0 7 * * ? *)`, still off until the first approved baseline |
| `iam-oidc` only RDS snapshot actions | Also: model_approve role publishes `baseline/*` and writes `evaluation/*/approval.json` |
| `terraform.yml` unchanged | Also runs on changes to `data/model-thresholds.yaml` (Terraform reads `drift.threshold`) |
| GitHub variables `DB_INSTANCE_ID`, `OPTIMIZATION_QUEUE_URL` | Plus `SMOKE_CHECK_LOGIN` from `okta_sign_in_enabled` (re-run `setup-github.ps1` after turning sign-in on) |
| – | `scripts/mock-plan.ps1` fixed (Windows PowerShell stopped on terraform stderr); monitoring dashboard conditional fixed (found by the all-features mock plan) |
| `devops_3_client_question.xlsx` needed | Generated (49 inputs, 12 decisions); `docs/01` points to it |

---

## 5. Proposed implementation order (after the user verifies this plan)

1. Remove Cognito; ALB `authenticate-oidc` with Okta (Step 8) + secret / SSM changes (Step 5).
2. Replace Aurora with RDS PostgreSQL + Proxy (Step 6); monitoring, backup and `deploy.yml` snapshot changes (Steps 10–12).
3. SQS + DLQ + dispatcher Lambda in front of the optimization state machine; API task role / env; queue alarms; dry run through the queue (Steps 3, 4, 7, 9, 10, 12).
4. Data platform: write-back states, model-monitor state machine + schedules, Unity Catalog permissions, governance baseline publishing, thresholds (Step 14).
5. Docs, runbooks, `data/README.md`, client questions v3, mock-plan expectations, `Project_memory.md`; update the `_3` files with what was built.

Each step: `terraform fmt/validate`, `validate-modules.ps1`, `sync-environments.ps1 -Check`,
`mock-plan.ps1` (new expected counts), tflint, Checkov, actionlint, shellcheck, secret scan.

---

## 6. Open questions and the proposed default

| # | Question | Proposed default [ASM] (to confirm with WBD) |
|---|---|---|
| 1 | **Okta at the ALB – OIDC or SAML?** One app per env? Groups claim? | **OIDC** web app per env (the ALB only speaks OIDC); `groups` claim with `mmm-bu-*` / `mmm-role-*`; MFA in Okta; client secret in Secrets Manager `mmm/<env>/okta/alb-client` (also in the encrypted Terraform state) |
| 2 | ALB OIDC vs app-level OIDC (PKCE in the UI, JWT check in the API)? | ALB `authenticate-oidc` – no auth code in the UI, API trusts the ALB-signed header (same pattern as v2) |
| 3 | **RDS PostgreSQL** – version, instance classes, Multi-AZ instance or Multi-AZ cluster, read replica, RDS Proxy? | PostgreSQL 16.x; dev `db.t4g.medium` single-AZ, staging `db.r6g.large` Multi-AZ, prod `db.r6g.xlarge` Multi-AZ; gp3 with storage autoscaling; no read replica; RDS Proxy kept |
| 4 | **SQS** – Standard or FIFO? Max concurrent runs? Fairness per BU / user? Max queue wait? | Standard queue + DLQ (`maxReceiveCount` 10); idempotent by execution name `run_id`; `max_concurrent_runs` dev 5 / stg 20 / prd 50 (≤ SageMaker quota); no per-BU fairness in v3 (FIFO order of arrival); 30 min max wait |
| 5 | Dispatcher – Lambda (slide) or EventBridge Pipes? Who owns the code? | Lambda as on the slide, DevOps-owned generic code (no business logic, no DB access), shipped by Terraform |
| 6 | **Write-back** – what goes back, every candidate or only approved models, which Gold tables, owner? | Predictions, lift and metrics of every registered version keyed by `refresh_id` + version, approval status from `approval.json`; Gold `gold.<bu>_model_results`; job owned by the data engineers |
| 7 | Write-back failure – fail the refresh? | Fails the execution and alarms; the registered model stays (approval is independent) |
| 8 | **Model drift** – definition, frequency, thresholds, auto-refresh? | Daily drift check per BU (built daily instead of the first-proposed weekly; schedule off until the first approved baseline); threshold 0.2; drift code by the data scientists (feature / prediction drift vs the approved baseline); `ModelDrift` metric + alarm; `auto_refresh_on_drift = false` (alert only) |
| 9 | SageMaker Model Monitor (managed)? | Not used – it needs an endpoint or batch transform; a Processing job runs the drift code (may use the Model Monitor container image) |
| 10 | Where do drift inputs come from? | The feature-export job with `purpose = monitor` writes the latest Gold features to `lakehouse/monitoring/<bu>/<date>/` (90-day expiry); the approved baseline is published to `models/baseline/<bu>/` on approval |
| 11 | Still open from v2 | Q1 ALB reachability / Shield Advanced; Q3 LLM data egress approval; Q4 Databricks IP access list; Q6 Databricks service principals; Anthropic via Bedrock; shared account. **Q2 (throttling) is answered by the SQS + dispatcher design; Q5 (Okta groups) moves to question 1 above** |

---

## 7. Session history

1. 6 Nov 2026: tools reinstalled after a VDI reset; full project walkthrough (v2); client deck
   `wbd_Presentation_3.pptx` reviewed against `wbd_Presentation.pptx`; v3 documents created in
   `docs/requirements/` (`devops_plan_3.txt`, this file, `aws_resource_list_3.xlsx`,
   `wbd_mmm_ecs_final_3.docx`, generator `tools/build_v3.py`). No platform code changed; not committed.
2. 6 Nov 2026: v3 implemented (section 4 + 4a): Cognito and Aurora removed, Okta OIDC at the ALB, RDS
   PostgreSQL, run queue + dispatcher, write-back, model monitor, governance baseline + approval
   record, pipelines, scripts, docs, runbooks, `devops_3_client_question.xlsx`. Offline validation
   passed (all tools clean; mock plan counts in the status line). `_3` xlsx/docx regenerated with an
   implementation column. Not committed.

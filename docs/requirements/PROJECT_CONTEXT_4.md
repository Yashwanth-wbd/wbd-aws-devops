# WBD MMM DevOps – Project Context v4 (updated client architecture)

Companion to `PROJECT_CONTEXT_3.md`. v3 (from `wbd_Presentation_3.pptx`) is **built** in this repo and
pushed to `main` (`59333f0`). This file describes the **v4 target** from the updated client deck
`WBD_MMM_Architecture_4.pptx` and what has to change in the code to get there.

Status (12 Nov 2026): **implemented and validated offline, not pushed yet** (fmt / validate, mock plan
dev 326 / 528, staging 341 / 545, prod 341 / 547, 26 modules validate, tflint, Checkov 1432 / 0,
actionlint, `bash -n`, `py_compile`). Where the build differs from this plan: §4a. The review
findings on the `_4` documents (data lineage, slide-1 Lambda label, IAM Identity Center and the
SageMaker ENI in the docx, GenAI timing) are deferred until the end; the `_4` xlsx / docx still show
the plan status until they are regenerated.

---

## 0. How to resume in a new chat

> I'm continuing the WBD MMM DevOps project, v4 architecture. Read `Project_memory.md` (root) and
> `docs/requirements/PROJECT_CONTEXT_4.md` first, then `docs/requirements/devops_plan_4.txt`. GitHub
> `Yashwanth-wbd/wbd-aws-devops`. Follow the rules in section 3 of `Project_memory.md`.
> Today I want to: <e.g. "implement v4 Step 9 (optimizer on ECS)">.

---

## 1. Documents

| File (`docs/requirements/`) | What it is |
|---|---|
| `WBD_MMM_Architecture_4.pptx` | **Client v4 architecture** – slide 1 "supports auto ML activities", slide 2 "supports optimization and explainable planning" (editable shapes; read with `tools/extract_pptx.py` or export the slides as images) |
| `devops_plan_4.txt` | v4 step-by-step build prompt (Steps 0–16); section A = change summary vs v3; **(v4)** marks every step that changes the built code |
| `aws_resource_list_4.xlsx` | Full v4 resource list (168 rows: kept + changed + new) plus sheets `summary`, `v4_new_resources` (45, names / sizes / repo location), `v4_changes` (17) and `removed_vs_v3` (13). Per environment: sheets dev/staging/prod; column "Change vs v3" (Same/Changed/New; yellow = new, green = changed, grey = owned by WBD / other teams or not planned) and "Repo today (v3 build) → v4 action" and "v4 build status" |
| `wbd_mmm_ecs_final_4.docx` | v4 design document (what changed, target platform, components, flows, environments, stages 0–17, questions with the proposed default, impact on the code, risks) |
| `devops_4_client_question.xlsx` | Full v4 list of inputs only WBD can provide (65, per environment; tagged New in v4 / Changed by v4 / From v3) + `decisions_to_confirm` (21) + `removed_vs_v3` (8 obsolete v3 questions) |
| `tools/build_v4.py`, `tools/build_client_questions.py` | Generate the `_4` xlsx / docx and the client-question workbook |
| `*_3.*`, `wbd_Presentation_3.pptx` | v3 inputs (what the current code implements) |

---

## 2. v4 architecture in one page

**Slide 1 – auto ML activities (Hybrid Platform Lakehouse + MLOps, auto-refresh, app-triggered refresh):**
EventBridge → Step Functions (schedule / manual, wait / retry) → **Lambda** → *Databricks API connector* →
**Databricks on AWS = "Databricks Source Catalog – responsible export via Jobs APIs"** → "**Raw data coming
from Databricks coming to S3**" (3+ years historical inventory) → **AWS Glue**: Bronze (ingested raw) →
Silver (cleansed and validated) → Gold (per-BU modeling tables, adstock & saturation) with "Glue Export"
arrows to **Delta Lake storage (S3)**, to **training data in S3** (immutable Parquet + metadata) and to **RDS
PostgreSQL** → SageMaker modeling (training → evaluation: baseline → channel lift → title adjustment →
model registration) → SageMaker Registry + S3 (approved models, response curves, model drift monitoring).
Evaluation → **Lambda results publisher → RDS PostgreSQL** ("model predictions, lift & evaluation results
written in RDS for the corresponding dataset"). The Lambda next to Databricks is labelled "Results
publisher" on the slide – read as a separate **Databricks export Lambda** [ASK].

**Slide 2 – optimization and explainable planning (50–150 concurrent planners, "with GenAI capabilities"):**
Planner (upload inventory + choose objective + run & compare **or upload future titles**) → DNS/WAF → ALB →
Okta (authentication + RBAC) → ECS UI (web + **QA dashboard**) ↔ ECS API (FastAPI + LangGraph tools,
**explanation tool by default for every run**) ↔ RDS PostgreSQL. API → **S3 "store user input files"**;
API → SQS → Lambda message dispatcher → Step Functions (async) → **"ECS Inference and Optimization Fargate
container"** (Model Summarizer · Optimizer · Simulation) reading the SageMaker Registry + approved response
curves in S3 → S3 outputs (full run evidence) → Lambda results publisher → RDS. API → Amazon API Gateway →
OpenAI / Anthropic / Google + Bedrock Guardrails. ECR, Route 53 · WAF · ACM unchanged.

Control plane, security + network and **logging / operations** bands are unchanged on both slides.

---

## 3. Service replacement map (v3 built → v4)

| v3 (built) | v4 | Type |
|---|---|---|
| Databricks Lakeflow refresh job (ingestion → Bronze → Silver → Gold → Feature Export), Delta Lake via Unity Catalog | **AWS Glue** jobs bronze / silver (+ Data Quality) / gold / export-training / export-rds / export-monitor, Glue Data Catalog, Delta Lake on the `lakehouse` bucket | Replaced |
| Source data dropped in `landing` and ingested by Databricks | **Databricks export Lambda** → Jobs API → WBD export job → `landing/raw/databricks/<bu>/<date>/` | Replaced |
| Step Functions HTTP Tasks to Databricks with an **EventBridge connection** (OAuth) | Lambda with the export SP secret in Secrets Manager (`databricks/export-sp`) | Replaced |
| Databricks **write-back** job (predictions, lift, evaluation → Gold) + write-back states | **Results publisher Lambda** (`model_results` event) → RDS PostgreSQL | Replaced |
| Unity Catalog role on landing, lakehouse, training-data, `models/evaluation/`, `lakehouse/monitoring/` | Unity Catalog role **write on `landing/raw/databricks/*` only** | Changed |
| Model-monitor export = Databricks job with `purpose = monitor` | Glue `export-monitor` job | Replaced |
| `databricks.yml` (Asset Bundle), `data/databricks/`, `DATABRICKS_CLIENT_ID` | `glue.yml`, `data/glue/`, `GLUE_ASSETS_BUCKET` | Replaced |
| **SageMaker Processing optimization job** (`mmm/sagemaker-optimizer`, SSM image pointer, run role, Processing quota) | **ECS Fargate task** `mmm-<env>-optimizer` (`mmm/optimizer`, SSM task-definition pointer, task role, Fargate quota) via `ecs:runTask.sync` | Replaced |
| Run input under `results/runs/<run_id>/input/` | **`uploads` bucket** (user input files, future titles; presigned upload) | New |
| – | `glue-assets` bucket (scripts, temp), `glue` endpoint + SG, Glue connection to RDS Proxy (`mmm_etl`, secret `rds/etl`) | New |
| GenAI only Release 2, optional | Explanation tool on every run (still behind `enable_genai`; Release 1 or 2 to confirm) | Changed |
| Everything else (ECR api/ui/training, ECS ui/api/migrate, ALB + Okta, WAF, ACM, DNS, RDS + Proxy, SQS + DLQ + dispatcher, optimization state machine shell, publisher Lambda, model-refresh shell, SageMaker training / evaluation / registry + governance, drift monitor, GenAI gateway, monitoring, backup, CI/CD) | same | Kept |

---

## 4. Impact on the current code (module by module)

| Path | v4 action |
|---|---|
| new `modules/glue` | Data Catalog databases, security configuration, NETWORK + JDBC (RDS Proxy) connections, jobs (bronze, silver, gold, export-training, export-rds, export-monitor), Data Quality ruleset (Silver), Glue role, log groups; README |
| new `modules/databricks-export` (or `lambda-function` + code path) [ASM] | Generic Databricks Jobs API Lambda (`start` / `status`), DevOps-owned like the dispatcher |
| `modules/databricks-access` | Unity Catalog role only writes `landing/raw/databricks/*`; remove lakehouse / training-data / models / monitoring access |
| `modules/network` | `glue` interface endpoint; `glue` SG (self-referencing); RDS Proxy SG from `glue`; optimizer uses the `tasks` SG |
| `modules/ecr` | `mmm/optimizer` replaces `mmm/sagemaker-optimizer` |
| `modules/sagemaker` | remove the optimization run role (training / evaluation stay) |
| `modules/monitoring` | Glue job / DQ / export Lambda / optimizer task alarms; `data-pipeline` dashboard; `optimization` dashboard on ECS tasks; remove write-back pieces |
| `modules/iam-oidc` | deploy role: register the optimizer task definition, PassRole, SSM pointer; upload Glue scripts + `glue:UpdateJob`; drop the optimizer image pointer |
| `environments/*/optimization.tf` | optimizer task definition + task role + log group + SSM pointer; state machine `ecs:runTask.sync`; remove SageMaker optimization pieces |
| `environments/*/data.tf` | export Lambda + secret + SSM job ids; Glue module; model-refresh states (export → Bronze → Silver → Gold → exports → train → evaluate → publish → register); model-monitor export via Glue; remove EventBridge connection, HTTP Tasks, write-back states |
| `environments/*/main.tf` | buckets `uploads`, `glue-assets`; secrets `databricks/export-sp`, `rds/etl`; SSM `databricks/export_job_ids`, `ecs/optimizer_task_definition` |
| `environments/*/ecs.tf` | API role + env for uploads; LLM gateway env for the explanation tool |
| `environments/*/variables.tf`, `terraform.tfvars` | remove `databricks_refresh_job_id`, `databricks_writeback_job_id`, `optimizer_instance_type`; add `optimizer_cpu`, `optimizer_memory`, `optimizer_ephemeral_storage_gib`, `databricks_export_job_ids`, `glue_version`, `glue_worker_type`, `glue_number_of_workers`, `glue_job_timeout_minutes`, `uploads_retention_days`, `enable_uploads_malware_scan` (each with `# add actual value` where WBD supplies it) |
| `environments/*/outputs.tf` | GitHub variables `OPTIMIZER_TASK_FAMILY`, `OPTIMIZER_TASK_PARAM`, `GLUE_ASSETS_BUCKET`, `UPLOADS_BUCKET`; drop `DATABRICKS_CLIENT_ID` |
| `environments/*/tests/mock-plan.tftest.hcl` | new expected counts |
| `ecs/<env>/optimizer.json` | NEW optimizer task-definition template; `api.json` env `UPLOADS_BUCKET` |
| `.github/workflows/` | `optimizer-ci` (ECS image), `deploy.yml` (optimizer revision + Glue scripts), new `glue.yml`, remove `databricks.yml` |
| `scripts/` | `dry-run-optimization.sh` (ECS task), `platform-check.sh` (Glue catalog, uploads), `trigger-model-refresh.sh`, `setup-github.ps1` (new variables, no `-DatabricksClientId`), `db-bootstrap.py` (`mmm_etl` user) |
| `data/README.md` | Glue job contract (paths, arguments, Delta tables, DQ rules, RDS export), Databricks export contract, `model_results` publisher event |
| `docs/` | 01, 05, 06, 08, 09, 10 (Databricks export + Glue), 11, 12; runbooks `model-refresh-failed`, `optimization-run-failed`, `scale-planning-season`, `rotation`, `deploy`, `rollback`, `model-drift`; new `glue-job-failed`, `databricks-export-failed`; remove `write-back-failed` |
| Unchanged | bootstrap, kms, permission-boundary (attached to new roles), budgets, secrets module, s3-bucket, log-bucket, rds, run-queue, ecs-cluster, ecs-service, alb, waf-regional, step-functions, lambda-function, log-shipping, backup, bedrock-guardrails, llm-gateway; workflows api/ui/training/publisher-ci, terraform, model-governance, repo-checks |

### 4a. Where the build differs from this plan

| Plan | Built | Why |
|---|---|---|
| `enable_uploads_malware_scan` variable (GuardDuty Malware Protection for S3, off) | **Not implemented** | Optional and off in the plan; stays an open question (§6 #13) |
| Optimizer task in the `tasks` security group | Dedicated `optimizer` security group (443 to the endpoints + S3 prefix list only) | Least privilege – the optimizer does not reach RDS |
| … → PublishModelResults → RegisterModel | RegisterModel → PublishModelResults | The RDS rows carry the `model_package_arn` |
| Glue export-rds as `mmm_etl` via the proxy | Same, plus secret `rds/etl` on the proxy and `db-bootstrap.py` creates `mmm_etl` when `ETL_SECRET_ID` is set; the Glue job uses an IAM token | The proxy needs a secret per DB user |
| Forecast file in `uploads/<bu>/titles/` | Every run (optimize and forecast) uses `uploads/<bu>/runs/<run_id>/input/`; `run_type` tells them apart | One path and one IAM scope for the API and the task |
| deploy role `glue:UpdateJob` (script version) | `glue:GetJob(s)` only; `glue.yml` overwrites `scripts/<job>.py` (the job always points at that key) | No job definition changes outside Terraform |
| Glue scripts uploaded by `deploy.yml` too | Only `glue.yml` | One path for data code; app releases stay independent |

---

## 5. Proposed implementation order (after the user verifies this plan)

1. Optimizer on ECS: ECR `mmm/optimizer`, task definition + role + SSM pointer, state machine `ecs:runTask.sync`, remove the SageMaker optimization pieces; `uploads` bucket + API role / env; optimizer-ci / deploy.yml / dry run (Steps 3, 6, 7, 9, 12).
2. Network and secrets for the data platform: `glue` endpoint + SG, RDS Proxy rule, `databricks/export-sp`, `rds/etl`, `glue-assets` bucket (Steps 4, 5, 6).
3. Data platform: `modules/glue`, Databricks export Lambda, reduced `databricks-access`, model-refresh and model-monitor states, publisher `model_results` event; remove the EventBridge connection and write-back (Step 14).
4. Monitoring (Glue, DQ, export, optimizer task), dashboards; `glue.yml`, remove `databricks.yml` (Steps 10, 12).
5. Docs, runbooks, `data/README.md`, mock-plan expectations, `Project_memory.md`; update the `_4` files with what was built.

Each step: `terraform fmt/validate`, `validate-modules.ps1`, `sync-environments.ps1 -Check`,
`mock-plan.ps1` (new expected counts), tflint, Checkov, actionlint, shellcheck, secret scan.

---

## 6. Open questions and the proposed default

| # | Question | Proposed default [ASM] (to confirm with WBD) |
|---|---|---|
| 1 | **Lambda next to Databricks is labelled "Results publisher"** – separate export Lambda? | Separate `mmm-<env>-databricks-export` Lambda (DevOps-owned generic code: Jobs API `run-now` + `runs/get`); the results publisher stays the RDS writer |
| 2 | **How does data leave Databricks?** Export job pushes to our S3, or the Lambda pulls? | WBD export job (Jobs API) writes Parquet to `landing/raw/databricks/<bu>/<date>/` through a Unity Catalog external location on our IAM role (write-only); the Lambda starts / polls it and writes `_manifest.json`. Pull via SQL Statement API only for small tables |
| 3 | Who owns the Databricks export job and the source catalog? | WBD Databricks / data engineers; we get the job id per BU (SSM `databricks/export_job_ids`) and a service principal for the Lambda |
| 4 | **Glue** – version, job type, table format, sizing? | Glue 5.0 Spark, Delta Lake (`--datalake-formats delta`) on the `lakehouse` bucket, Data Catalog databases bronze / silver / gold; G.1X, 2 / 5 / 10 workers dev / stg / prd; job bookmarks; 120-min timeout |
| 5 | Glue orchestration – Glue workflows / triggers or Step Functions? | Step Functions `glue:startJobRun.sync` per layer inside `model-refresh` (one orchestrator, same retries / alarms) |
| 6 | **Lake Formation** needed? | No – IAM role + bucket policies + per-BU KMS; turn on if WBD requires table-level grants |
| 7 | Silver "cleansed and validated" – how is data validated? | Glue Data Quality ruleset in the Silver job (rules by the data engineers); failure stops the refresh and alarms |
| 8 | **Glue export to RDS** – which data, which user, direct or via Proxy? | Gold per-BU reference tables needed by the app; JDBC connection to **RDS Proxy** with DB user `mmm_etl` (secret `rds/etl`); tables created by the backend's Alembic migrations |
| 9 | Model results to RDS – which Lambda? | Same results-publisher function with a new `model_results` event (predictions, lift, evaluation); backend team code |
| 10 | **Optimizer on ECS** – one task per run or a worker service? | `ecs:runTask.sync` per run from Step Functions (isolation, simple cancel); worker service polling SQS as an alternative if start-up time matters |
| 11 | Optimizer task size and Fargate quota? | 4 vCPU / 16 GB / 50 GB ephemeral; Fargate vCPU quota ≥ `max_concurrent_runs` × 4 + services (prod 50 × 4 = 200 vCPU + ~40) |
| 12 | `max_concurrent_runs` with ECS | Unchanged 5 / 20 / 50 (now bounded by the Fargate quota, not SageMaker) |
| 13 | **User input files** – upload path, retention, malware scan? | New `uploads` bucket, presigned PUT from the API (CORS for the app domain), per-BU prefix + key, 90-day expiry, versioned, not in AWS Backup; GuardDuty Malware Protection for S3 optional (off) |
| 14 | "Upload future titles" | New run type `forecast` on the same queue, state machine and optimizer image; file in `uploads/<bu>/titles/` |
| 15 | **Explanation tool on every run → GenAI in Release 1?** | Stays behind `enable_genai` (off until WBD approves data egress or Bedrock-hosted models); the run succeeds without the explanation; token quota sized per run (≈5,000 tokens per explanation) |
| 16 | Drift monitoring inputs | Glue `export-monitor` writes `lakehouse/monitoring/<bu>/<date>/`; rest of the v3 drift design unchanged |
| 17 | Still open from v3 | ALB reachability / Shield Advanced; LLM data egress (now more important); Databricks IP access list (export Lambda NAT IPs); Okta groups; RDS sizes; Anthropic via Bedrock; shared account |

---

## 7. Session history

1. 12 Nov 2026: tools reinstalled on a new VDI; v3 build re-validated and re-read; architecture review
   (missing services) and two draft decks (not kept); client deck `WBD_MMM_Architecture_4.pptx` reviewed
   against `wbd_Presentation_3.pptx`; v4 documents created in `docs/requirements/` (`devops_plan_4.txt`,
   this file, `aws_resource_list_4.xlsx`, `wbd_mmm_ecs_final_4.docx`, `devops_4_client_question.xlsx`,
   generator `tools/build_v4.py`). No platform code changed; not committed.
2. 12 Nov 2026: review of the `_4` documents (gaps listed in the status note – deferred by the user);
   **v4 implemented** in the order of §5 (modules `glue`, `databricks-export`; optimizer ECS task;
   `uploads` / `glue-assets`; state machines; monitoring; `glue.yml`; deploy, dry run, scripts; docs,
   runbooks, READMEs, `Project_memory.md`). Validated offline; waiting for the user to push.

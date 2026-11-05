# WBD MMM DevOps – Project Context v2 (new client architecture)

Companion to `PROJECT_CONTEXT.md` (v1, project root). v1 describes what is **built** in this repo
(Steps 0–15 of `devops_plan_1.txt`). This file describes the **v2 target** from the client deck
`wbd_Presentation.pptx` and what has to change in the code to get there.

Status (5 Nov 2026): **v2 is implemented in the code** (all environments, pushed to `main`). The
open questions in section 6 were implemented with the simpler industry-standard default shown there;
`PROJECT_CONTEXT.md` (root) is now the v2 continuation guide and lists what WBD still has to confirm
(§5.2 Q1–Q6). Sections 2–5 below are the original plan; section 4a lists where the build differs.

---

## 0. How to resume in a new chat

> I'm continuing the WBD MMM DevOps project, v2 architecture. Read `PROJECT_CONTEXT.md` (root) and
> `docs/requirements/PROJECT_CONTEXT_2.md` first, then `docs/requirements/devops_plan_2.txt`. The
> project is at `\\USE_EIS_NTPCFS1.tw.tweis.net\WMAD_Profiles\yn\Desktop\wbd_devops\wbd_devops_implmenetation_1`
> (GitHub `Yashwanth-wbd/wbd-aws-devops`). Follow the rules in section 3 of `PROJECT_CONTEXT.md`.
> Today I want to: <e.g. "implement v2 Step 6 (Aurora)">.

---

## 1. Documents

| File (`docs/requirements/`) | What it is |
|---|---|
| `wbd_Presentation.pptx` | **Client v2 architecture** – slide 1 "supports auto ML training", slide 2 "supports optimization and explainable planning" (both slides are images) |
| `devops_plan_2.txt` | v2 step-by-step build prompt (Steps 0–16), section A = change summary vs v1 |
| `aws_resource_list_2.xlsx` | v2 resources in creation order, sheets dev/staging/prod (145/150/151 rows; column "Change vs v1" = Same/Changed/New, yellow = new, green = changed, grey = not built; column "Implemented (5 Nov 2026)") + sheets `removed_vs_v1` (19 items) and `decisions` (defaults implemented) |
| `wbd_mmm_ecs_final_2.docx` | v2 design document (target platform, flows, environments, stages 0–17, questions with the implemented default, implementation status, risks) |
| `devops_plan_1.txt`, `aws_resource_list.xlsx`, `wbd_mmm_ecs_final.docx` | v1 inputs (what the current code implements) |

---

## 2. v2 architecture in one page

**Slide 1 – auto ML training (Hybrid Lakehouse + MLOps, auto-refresh, app-triggered refresh):**
Scheduled refresh → **EventBridge → Step Functions** (schedule/manual, wait/retry) → **Databricks on
AWS** (data engineering + private VPC compute): **Lakeflow Jobs** → ingestion from S3 into the DBX
catalog → **Bronze** (raw) → **Silver** (cleansed, validated) → **Gold** (per-BU modeling tables,
adstock & saturation) → **Feature Export** (plans, runs, allocations). Raw landing from S3 (3+ years of
history); **Delta Lake storage backed by S3**. **Step Functions** publishes **Parquet + metadata to S3**
(training data, immutable) → **SageMaker modeling** (VPC ENI): model training (multi-stage) →
evaluation (baseline → channel lift → title adjustment) → model registration → **SageMaker Registry + S3**
(approved models + response curves).

**Slide 2 – optimization and explainable planning (50–150 concurrent planners):**
Planner → **DNS/WAF** → **ALB (HTTPS, public entry)** → **ECS UI** (Fargate web container) → **ECS API**
(Fargate, FastAPI + **LangGraph** + **QA dashboard**) ↔ **Aurora PostgreSQL** (plans, runs, allocations).
**Cognito** (SSO, enterprise IdP). **ECR** (UI + API images, versioned). API → **Step Functions (async)**
→ **SageMaker job for optimization & decision** (Model Summarizer · Optimizer · Simulation) reading
**SageMaker Registry** + **approved response curves in S3** → **S3 outputs (full run evidence)** →
**Lambda results publisher** → Aurora. API → **Amazon API Gateway** → **OpenAI / Anthropic / Google
models** + **Amazon Bedrock Guardrails**.

**Both slides:** control plane = data lineage & observability, code repository, security (RBAC,
SSO/MFA), Bedrock for GenAI, privacy & GenAI guardrails. Security + network = IAM role assumption,
Identity Center, KMS, Secrets Manager, SGs, VPC routes. Operations = CloudWatch metrics, CloudTrail,
Terraform, CI/CD. Prescribed stack: React + TypeScript, Python/FastAPI, scikit-learn/XGBoost/LangGraph,
SciPy, RDS PostgreSQL + Databricks/S3, ECS.

---

## 3. Service replacement map (v1 plan/code → v2)

| v1 (built) | v2 | Type |
|---|---|---|
| CloudFront + OAC + KVS release switch + us-east-1 WAF/ACM | Route 53 → regional WAF → public ALB | Replaced |
| React static site in S3 (`frontend` bucket, `frontend-ci` S3 publish) | `mmm-ui` ECS Fargate container (`mmm/ui` image) | Replaced |
| Okta app per env used directly | Cognito user pool federated to Okta | Replaced |
| RDS PostgreSQL instance (+ RDS Proxy) | Aurora PostgreSQL cluster (+ RDS Proxy for Lambda) | Replaced [ASK] |
| ECS `whatif-worker` + `optimizer-worker`, SQS FIFO + DLQ, backlog scaling, scale-in protection | Step Functions → SageMaker optimization & decision job → S3 outputs → Lambda publisher | Replaced |
| ElastiCache Valkey | – | Removed [ASK] |
| MWAA + MWAA bucket + data-trigger Lambda | EventBridge (+ Scheduler) → Step Functions → Databricks Lakeflow Jobs | Replaced |
| Great Expectations `data-quality` bucket | Lakeflow (Silver "cleansed and validated") | Replaced [ASK] |
| MLflow (Unity Catalog) `production` alias, `model-governance.yml` alias move | SageMaker Model Registry approval status + S3 response curves | Replaced |
| Databricks training | SageMaker training + evaluation jobs | Replaced |
| ECS `genai-gateway` + Service Connect + Bedrock-only PrivateLink policy | LangGraph in the API + API Gateway LLM gateway (OpenAI/Anthropic/Google) + Bedrock Guardrails (ApplyGuardrail) | Replaced |
| `data.yml` (DAGs → MWAA) | Databricks Asset Bundles pipeline | Replaced |
| ECR `mmm/optimizer-worker`, `mmm/genai-gateway` | `mmm/ui`, `mmm/sagemaker-optimizer`, `mmm/sagemaker-training` | Replaced |
| Terraform, GitHub OIDC, ECR per env + promotion, ECS cluster, ALB, KMS, Secrets/SSM, VPC, SGs, endpoints, CloudWatch, CloudTrail, AWS Backup, budgets, permission boundary, Databricks PrivateLink/UC role, TGW/Resolver | same | Kept |

---

## 4. Impact on the current code (module by module)

| Path | v2 action |
|---|---|
| `infra/bootstrap` | keep |
| `modules/kms` | keep; add purpose `sagemaker`; drop `sqs` if SQS removed |
| `modules/permission-boundary` | keep (covers new SageMaker/Step Functions/Lambda/Scheduler roles) |
| `modules/iam-oidc` | change: deploy role → `mmm-ui` service, SSM image params; new model-approval permissions; drop frontend S3/CloudFront/KVS + MWAA statements |
| `modules/budgets` | keep; add SageMaker budget |
| `modules/network` | change: ALB SG from internet/WBD ranges (drop CloudFront prefix list), new SGs ui / sagemaker / lambda, drop redis/mwaa/genai SGs, endpoints + `states`, `sagemaker.api` (+ `sagemaker.runtime`), R2 `execute-api`, drop `sqs` |
| `modules/secrets` | keep; secret list changes (drop `redis/token`, `edge/origin-verify`; add LLM keys in R2) |
| `modules/ecr` | keep; repo list changes |
| `modules/s3-bucket`, `log-bucket` | keep; bucket set changes (add lakehouse, training-data, models, outputs, sagemaker-staging; drop frontend, mwaa, data-quality) |
| `modules/rds` | **replace** with new `modules/aurora` (cluster, instances, cluster/DB parameter groups, Proxy) |
| `modules/elasticache`, `modules/sqs` | **remove** (unless WBD keeps them) |
| `modules/ecs-cluster`, `ecs-service` | keep (Service Connect optional) |
| `modules/alb` | change: 2 target groups + path rules, `authenticate-cognito`, HTTP→HTTPS redirect, drop origin-verify header rule, WAF association |
| `modules/edge` | **remove** (CloudFront); new `modules/waf-regional` (reuse `waf.tf` rules with scope REGIONAL) |
| new `modules/cognito` | user pool, Okta IdP, UI client, domain, resource server, groups |
| new `modules/step-functions` | state machine + role + log group (used for optimization and model-refresh) |
| new `modules/sagemaker` | execution roles (optimization, training, evaluation), model package groups per BU, KMS/VPC settings, EventBridge rule on model package state |
| new `modules/lambda-function` | results publisher (VPC, DLQ, logs) |
| `modules/mwaa`, `modules/data-trigger` | **remove** |
| `modules/databricks-access` | keep; add lakehouse/training-data external locations; optional customer-managed VPC |
| `modules/bedrock` | **reshape** to `bedrock-guardrails` (guardrail + runtime endpoint + logs); invocation-logging/approved-model policy only if Bedrock models are used |
| new `modules/llm-gateway` (R2) | private API Gateway, per-provider Lambda integrations, usage plans, logs |
| `modules/monitoring`, `backup`, `log-shipping` | keep; alarm/dashboard/selection inputs change (Aurora, Step Functions, SageMaker, Lambda) |
| `environments/*/ecs.tf` | change: services → api + ui (+ migrate); drop workers; task-role policies change |
| `environments/*/edge.tf` | replace with WAF regional + Cognito wiring |
| `environments/*/data.tf` | replace MWAA/data-trigger with scheduler + model-refresh state machine + SageMaker training side |
| `environments/*/genai.tf` | replace ECS gateway with llm-gateway + guardrails (R2) |
| new `environments/*/optimization.tf` | optimization state machine, SageMaker run role, publisher Lambda |
| `ecs/<env>/` | keep `api.json`, `migrate.json`; add `ui.json`; delete `whatif-worker.json`, `optimizer-worker.json`, `genai-gateway.json` |
| `.github/workflows` | `api-ci` keep; `frontend-ci` → `ui-ci` (container); `optimizer-ci`/`genai-ci` → `sagemaker-image-ci`; `deploy.yml` change (ui service, optimizer image tag, Aurora snapshot, drop S3/CloudFront frontend publish and worker deploys); `data.yml` → `databricks.yml`; `model-governance.yml` → SageMaker model package approval; `terraform.yml`, `repo-checks.yml` keep |
| `scripts/` | drop `deploy-frontend.sh`; `trigger-ondemand.sh` → start model-refresh execution / put `mmm.refresh`; `promote-images.sh`, `ecs-deploy.sh`, `smoke.sh`, `run-migration.sh` keep (+ ui) ; `model_governance.py` rewrite for SageMaker |
| `apps/genai-gateway` | remove (LangGraph lives in the dev team's API) |
| `data/` | DAG, manifest schema → replaced by Databricks bundle + run manifest for the Parquet export; `model-thresholds.yaml` keep |
| `docs/` | 03, 04 (Okta → Cognito), 08, 09, 10, 12, runbooks update |

The v1 defects D1–D4 are fixed (Trivy `version:`, drift skip without role, skopeo in `deploy.yml`,
`github_org`/`github_repo` = `Yashwanth-wbd`/`wbd-aws-devops`).

### 4a. Where the build differs from the plan above (simpler default chosen)

| Plan | Built |
|---|---|
| Buckets `outputs`, `sagemaker-staging` | Run evidence in the kept `results` bucket (`runs/<run_id>/`); no staging bucket |
| Cognito resource server + groups | Not built – RBAC from the Okta `groups` SAML attribute (`custom:groups`); ALB auth needs no scopes |
| Publisher Lambda with DLQ | No DLQ – Step Functions invokes the `live` alias synchronously with retries; failures alarm |
| `sagemaker-image-ci` | `optimizer-ci`, `training-ci`, `publisher-ci` via `_python-service-ci` (`build_image` input) |
| `trigger-ondemand.sh` → start execution | `trigger-model-refresh.sh` puts an `mmm.refresh` event (one BU or `all`) |
| LLM gateway: Lambda per provider + usage plans per BU | One proxy Lambda for all providers; stage throttling; per-BU token quotas enforced by the API |
| Budgets: SageMaker / LLM budgets | Not built – account budget + Cost Anomaly Detection |
| `databricks-access`: optional customer-managed VPC | Not built – WBD workspace; PrivateLink optional (off) |
| `data-v*` tags for Databricks jobs | No separate tags – `databricks.yml` deploys the bundle on merge to main (dev) or by dispatch |
| Databricks credentials secret | Held by the EventBridge connection (OAuth client credentials) |
| Autoscaling API on CPU/requests | CPU target tracking (60 %) for api and ui |
| Data platform and GenAI | Built but **off** (`enable_data_platform`, `enable_genai` = false) |
| Cognito advanced security (threat protection) in prod [ASK] | Not built – AWS threat protection does not cover federated (Okta) sign-in; risk checks and MFA stay in Okta |
| Alarm "Lambda publisher DLQ not empty", separate SageMaker job failure alarm | Not needed – no DLQ; SageMaker job failures fail the state machine (`-failed`) |
| Availability < 99.5 % in business hours | Hourly availability alarm over all hours |
| Optimization runtime standard > 2 min / large > 10 min | `optimization-standard-p95` (app metric `OptimizeDurationMs`, `RunSize = standard`) and `optimization-runtime-max` (Step Functions `ExecutionTime` > 10 min) |
| Training data stale | `model-refresh-overdue` (no successful refresh in 7 days) + refresh failure alarm; failed thresholds via the model package state event |
| SSM `stepfunctions/*`, `databricks/job_ids`, `sagemaker/model_package_group/<bu>` | Not built – state machine ARNs in the API task env and GitHub variables; job id = `databricks_refresh_job_id`; group name `mmm-<env>-<bu>`; image pointers `/mmm/<env>/images/sagemaker-*` |
| Evaluation states baseline → channel lift → title adjustment | One evaluation Processing job; the three stages are inside the data scientists' code |
| Optimizer loads the latest Approved package | Approval (`model-governance.yml`) publishes the curves to `models/curves/<bu>/`; the optimizer reads that prefix |

---

## 5. Proposed implementation order (done 5 Nov 2026 – kept for reference)

1. Fix v1 defects D1–D4 (they affect kept code).
2. v2 Step 6: `modules/aurora` replacing `rds` (+ Proxy), bucket set change, ECR repo change.
3. v2 Step 7 + 8: ALB path routing, `mmm-ui` service, `waf-regional`, `cognito`; remove `edge`, frontend bucket.
4. v2 Step 9: optimization engine (`step-functions`, `sagemaker` run side, `lambda-function`); remove workers, SQS, ElastiCache.
5. v2 Step 10–12: monitoring/backup/CI-CD changes (`ui-ci`, `sagemaker-image-ci`, `deploy.yml`).
6. v2 Step 14: model-refresh pipeline, SageMaker training side, Databricks bundles, governance; remove MWAA/data-trigger.
7. v2 Step 15 (R2): `llm-gateway` + `bedrock-guardrails`; remove `genai-gateway`.
8. Docs/runbooks, mock-plan expectations, `PROJECT_CONTEXT.md` update.

Each step: `terraform fmt/validate`, `validate-modules.ps1`, `mock-plan.ps1` (expected counts change),
tflint, Checkov, actionlint, `sync-environments.ps1 -Check`.

---

## 6. Open questions and the default implemented

| # | Question | Default implemented (confirm with WBD where marked) |
|---|---|---|
| 1 | **Aurora vs RDS**, provisioned or Serverless v2, RDS Proxy? | Aurora PostgreSQL **Serverless v2** 16.6 + RDS Proxy (IAM auth, TLS) |
| 2 | **Cognito** – OIDC or SAML, IdP owner, auth at ALB or in app? | **SAML** federation to Okta; ALB `authenticate-cognito`; WBD IAM owns the Okta app (confirm group names – Q5) |
| 3 | **CloudFront removed**, ALB public or WBD ranges, Shield Advanced? | Removed; public ALB + regional WAF + Cognito; `alb_ingress_cidrs` to restrict; no Shield Advanced (**Q1**) |
| 4 | **ElastiCache and SQS dropped** – progress and throttling? | Dropped; progress = Step Functions execution status + run row in Aurora; throttling = Step Functions retries on SageMaker limits + app-side concurrency limit (**Q2**) |
| 5 | **What-if ≤ 10 s** | What-if runs in the API; SageMaker only for full optimization runs |
| 6 | **SageMaker** job type, instances, quotas, warm pools, Studio? | Processing jobs; `ml.m5.xlarge` (optimizer/evaluation), `ml.m5.2xlarge` (training); quota request before load test; no warm pools; no Studio |
| 7 | **Databricks** workspace, compute, deployment? | WBD workspace; Step Functions HTTP Task through an EventBridge connection; Asset Bundle via `databricks.yml` (GitHub OIDC); confirm IP access list (**Q4**) and service principals (**Q6**) |
| 8 | **GenAI** gateway, providers, data leaving AWS? | Our private API Gateway + proxy Lambda; providers in `llm_providers`; guardrail on every call; **written approval needed (Q3)** |
| 9 | **Release split** | GenAI stays Release 2 (`enable_genai = false`) |
| 10 | **Splunk** | CloudWatch primary; Firehose → Splunk built, off until the HEC endpoint is known |
| 11 | **MLflow** | Replaced by the SageMaker Model Registry (`model-governance.yml`) |
| 12 | **Shared account** | Not built (GitHub-hosted runners) – still to confirm |

---

## 7. Session history

1. 5 Nov 2026: tools reinstalled after VDI reset, `gh` logged in; full review of v1 code vs
   `devops_plan_1.txt` / docx / xlsx (gaps listed in chat; D1–D4 still open); client v2 deck reviewed;
   v2 documents created in `docs/requirements/` (`devops_plan_2.txt`, `aws_resource_list_2.xlsx`,
   `wbd_mmm_ecs_final_2.docx`, this file). No code changed; not committed yet.
2. 5 Nov 2026: v2 implemented (modules, dev stack synced to staging/prod, ECS templates, workflows,
   scripts, docs, `PROJECT_CONTEXT.md`); open points implemented with the defaults in section 6;
   xlsx/docx regenerated with an implementation-status column/section. Pushed to `main`
   (`89382f2`, `bf4a051`).
3. 5 Nov 2026: review against `devops_plan_2.txt`; the missing plan items were built – Step 9 alarms
   (availability, Aurora connections / local storage / replica lag, optimization runtime, Step
   Functions throttling, model refresh overdue, LLM 4xx / latency, token quota) and dashboards
   (platform, api-ui, optimization, training, aurora, cost, genai); Step 11 backup of `training-data`
   and `lakehouse`; Step 12 post-release optimization dry run and actions pinned to commit SHAs.
   Doc and xlsx corrections. Still open: SBOM, DAST, cosign, CODEOWNERS, performance tests.

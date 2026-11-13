# WBD MMM DevOps – Project Context v5 (updated client architecture)

Companion to `PROJECT_CONTEXT_4.md`. v4 (from `WBD_MMM_Architecture_4.pptx`) is **built** in this repo
(`e2cac7b`). This file describes the **v5 target** from the updated client deck
`WBD_MMM_Architecture_5.pptx` and what has to change in the code to get there.

Status (13 Nov 2026): **plan only – not implemented.** The v5 documents are in `docs/requirements/`;
the code is changed only after the user has reviewed them. v5 keeps the v4 layout and services – the
change is moderate (one data path, lineage, audit and labelling), not a redesign.

---

## 0. How to resume in a new chat

> I'm continuing the WBD MMM DevOps project, v5 architecture. Read `Project_memory.md` (root) and
> `docs/requirements/PROJECT_CONTEXT_5.md` first, then `docs/requirements/devops_plan_5.txt`. GitHub
> `Yashwanth-wbd/wbd-aws-devops`. Follow the rules in section 3 of `Project_memory.md`.
> Today I want to: <e.g. "implement v5 Step 14 (Gold → RDS through the publisher)">.

---

## 1. Documents

| File (`docs/requirements/`) | What it is |
|---|---|
| `WBD_MMM_Architecture_5.pptx` | **Client v5 architecture** – slide 1 "supports auto ML activities", slide 2 "supports optimization and explainable planning" (read with `tools/extract_pptx.py` or export the slides as images) |
| `devops_plan_5.txt` | v5 step-by-step build prompt (Steps 0–16); section A = change summary vs v4; **(v5)** marks every step that changes the built code |
| `aws_resource_list_5.xlsx` | Complete v5 resource list (219 rows) in the `_4_new` layout: `all_resources` with dev / staging / prod values, sheets `dev` / `staging` / `prod` with real names, `architecture_flow`, `alarms_and_events`, `outside_aws`, `summary`; filter columns **Release**, **Scope** and **Change vs v4** (New 3 / Changed 14 / Same); sheets `v5_changes` and `removed_vs_v4` (4) |
| `wbd_mmm_ecs_final_5.docx` | v5 design document (what changed vs v4, target platform, flows, environments, impact on the v4 code, stages, risks, resource summary, questions with the proposed default) |
| `devops_5_client_question.xlsx` | Inputs only WBD can provide (68, per environment; **v5 status** New in v5 / Changed by v5 / From v4) + `decisions_to_confirm` (24) + `removed_vs_v4` (3 questions v5 answers) |
| `tools/build_v5.py` | Generates the three v5 xlsx / docx files |
| `*_4.*`, `*_4_new.xlsx`, `WBD_MMM_Architecture_4.pptx` | v4 inputs (what the current code implements) |

---

## 2. v5 architecture in one page

**Slide 1 – auto ML activities:** EventBridge → Step Functions (schedule / manual / app-triggered, wait /
retry) → **"Lambda Functions – Export Trigger"** → Databricks API connector → Databricks source catalog
export (Jobs API) → raw data in S3 (3+ years) → **"AWS Glue + Data Catalog (Lineage)"**: Bronze → Silver
(cleansed and validated) → Gold (per-BU modeling tables, adstock & saturation) on Delta Lake (S3) → Glue
exports: Gold → training data (immutable Parquet + metadata) and **Gold → "Lambda Functions – Results/data
publisher" → RDS PostgreSQL** → SageMaker training → evaluation (baseline → channel lift → title
adjustment) → registration → SageMaker Registry + S3 (approved models, curves, drift monitoring **+
lineage**). Model predictions, lift & evaluation → results/data publisher → RDS.

**Slide 2 – optimization and explainable planning:** Planner → DNS/WAF → ALB → Okta (authentication + RBAC,
**IAM Identity Center** drawn under it) → ECS UI (web + QA dashboard, **"User file upload to S3"**) ↔ ECS API
(FastAPI + LangGraph tools) ↔ RDS. API → SQS → dispatcher Lambda → Step Functions → ECS inference &
optimization task → S3 outputs → results publisher → RDS. **GenAI box (API Gateway, Bedrock Guardrails,
OpenAI / Anthropic / Google) marked "Not part of R1".**

**Both slides:** "AWS IAM" on every integration arrow, "KMS" on every data store, and a new box
**"Environment level component"**: Secrets Manager, VPC routes, CloudWatch, CloudTrail "enabled across all
components". Control plane and the security / logging bands are unchanged.

---

## 3. Change map (v4 built → v5)

| v4 (built) | v5 | Type |
|---|---|---|
| Glue `export-rds` → JDBC → RDS Proxy as `mmm_etl` (secret `rds/etl`, Glue in `data-clients`, `rds-db:connect`) | Glue `export-rds` → `lakehouse/rds-export/<bu>/<refresh_id>/` → results/data publisher (`reference_data`, `mmm_app`) → RDS | Changed |
| Model-refresh … → `ExportToRds` → Train → Evaluate → Register → PublishModelResults | … → `ExportReferenceData` → **`PublishReferenceData`** → Train → Evaluate → Register → **`RecordLineage`** → PublishModelResults | Changed |
| No lineage records | Glue catalog table properties per refresh + SageMaker ML Lineage Tracking; DataZone optional | New |
| CloudTrail = WBD org trail (management events) | + S3 data events on the MMM data buckets (WBD org trail; our trail only if asked) | New (optional) |
| Lambda "Results publisher" next to Databricks (read as the export Lambda) | Slide label "Export Trigger" | Confirmed |
| GenAI Release 2 (open: R1?) | "Not part of R1" | Confirmed |
| Presigned browser upload to `uploads` | Arrow "User file upload to S3" | Confirmed |
| IAM Identity Center (baseline) | Under Okta → Okta as identity source | Confirm with WBD |
| Everything else | same | Kept |

---

## 4. Impact on the current code (module by module)

| Path | v5 action |
|---|---|
| `modules/glue` | Connection without `data-clients` / JDBC; role without `rds-db:connect`, with `glue:UpdateTable` on the MMM databases (lineage properties); `export-rds` argument `--output_uri` |
| `modules/network` | Glue SG egress 443 only; `data-clients` no longer attached to Glue |
| `environments/*/data.tf` | Glue module inputs; model-refresh states `ExportReferenceData`, `PublishReferenceData`, `RecordLineage`; refresh role + SageMaker lineage APIs |
| `environments/*/optimization.tf` | Publisher role reads `lakehouse/rds-export/*` + per-BU lakehouse keys; `publisher_timeout_seconds` / memory |
| `environments/*/main.tf` | Remove secret `rds/etl` and its RDS Proxy auth entry; lakehouse lifecycle `rds-export/` (30 days) |
| `environments/*/variables.tf`, `terraform.tfvars` | `enable_cloudtrail_data_events` (false), `publisher_timeout_seconds`; remove ETL-user inputs |
| `environments/*/monitoring.tf`, `modules/monitoring` | `data-pipeline` dashboard: rows published, lineage records; optional CloudTrail data-event trail |
| `environments/*/tests/mock-plan.tftest.hcl` | New expected counts |
| `scripts/db-bootstrap.py` | Remove `mmm_etl` / `ETL_SECRET_ID` |
| `data/README.md` | `export-rds` output contract, publisher `reference_data` event, lineage table properties |
| `docs/` + runbooks | 05, 06, 08, 10; `model-refresh-failed`, `glue-job-failed`, `rotation`, `databricks-export-failed` (Export Trigger) |
| Unchanged | bootstrap, kms, permission-boundary, iam-oidc, ecr, ecs-*, alb, waf, rds module, run-queue, step-functions, lambda-function, databricks-export, databricks-access, sagemaker, backup, bedrock-guardrails, llm-gateway; all workflows |

---

## 5. Proposed implementation order (after the user verifies this plan)

1. Gold → RDS through the publisher: Glue module / network changes, remove `rds/etl` + `mmm_etl`, lakehouse `rds-export/` lifecycle, publisher role / timeout, model-refresh `ExportReferenceData` + `PublishReferenceData` (Steps 2, 4, 5, 6, 9, 14).
2. Lineage: Glue `UpdateTable`, `RecordLineage` state + refresh role (Step 14).
3. Monitoring and the optional CloudTrail data events (Step 10).
4. Docs, runbooks, `data/README.md`, mock-plan expectations, `Project_memory.md`; regenerate the `_5` files with the build status.

Each step: `terraform fmt/validate`, `validate-modules.ps1`, `sync-environments.ps1 -Check`,
`mock-plan.ps1`, tflint, Checkov, actionlint, secret scan.

---

## 6. Open questions and the proposed default

| # | Question | Proposed default [ASM] (to confirm with WBD) |
|---|---|---|
| 1 | **Gold → RDS through the results/data publisher** – does Glue stop writing to RDS? | Yes – `export-rds` writes Parquet to `lakehouse/rds-export/`; the publisher (`reference_data`) loads RDS as `mmm_app`; `mmm_etl` / `rds/etl` removed |
| 2 | Reference tables too large for a 15-minute Lambda? | Batched load per table; fallback = v4 direct Glue write for that table |
| 3 | **Lineage** – what and where? | Glue catalog table properties + SageMaker ML Lineage Tracking (export → Gold → training data → training job → model package); no extra service |
| 4 | Lineage UI (Amazon DataZone / SageMaker Catalog)? | Not in Release 1; optional |
| 5 | **CloudTrail "enabled across all components"** | WBD org trail adds S3 data events for the 7 MMM data buckets; we verify |
| 6 | **IAM Identity Center under Okta** | Okta is the Identity Center identity source for engineers; planners use the Okta app at the ALB |
| 7 | Explanation tool "by default for every run" while GenAI is "Not part of R1" | Skipped in Release 1; enabled with GenAI in Release 2 |
| 8 | Still open from v4 | Databricks export job ownership, Lake Formation (no), malware scan (off), ALB reachability, LLM data egress, RDS sizes, Fargate / Glue quotas |

Answered by v5 (removed from the question list): separate export Lambda (yes – "Export Trigger");
GenAI in Release 1 (no – "Not part of R1"); `mmm_etl` Glue DB user (no longer needed).

Note: `aws_resource_list_4_new.xlsx` names the DB users `mmm_migrate` / `mmm_etl`; the code uses
`mmm_migrator` (and v5 drops `mmm_etl`). The `_5` files use the code names.

---

## 7. Session history

1. 13 Nov 2026: client deck `WBD_MMM_Architecture_5.pptx` added to `docs/requirements/` and compared with
   `WBD_MMM_Architecture_4.pptx` (slide text + rendered images); v5 documents created (`devops_plan_5.txt`,
   this file, `aws_resource_list_5.xlsx`, `wbd_mmm_ecs_final_5.docx`, `devops_5_client_question.xlsx`,
   generator `tools/build_v5.py`; `tools/extract_pptx.py` skips linked images). No platform code changed; not committed.

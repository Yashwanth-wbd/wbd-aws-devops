# WBD MMM DevOps – Project Context v6 (final client architecture)

Companion to `PROJECT_CONTEXT_5.md`. v5 (from `WBD_MMM_Architecture_5.pptx`) is **built** in this repo
(`415caef`). This file describes the **v6 target** from the final client deck
`WBD_MMM_Architecture_6.pptx` and what has to change in the code to get there.

Status (17 Nov 2026): **plan only – not implemented.** v6 keeps slide 1 (auto ML activities) and the data
platform as built; slide 2 changes the entry point (internal ALB, no public entry) and the GenAI path
(Amazon Bedrock directly through the `bedrock-runtime` VPC endpoint, no API Gateway LLM gateway).

**Delivery model (confirmed by WBD):** WBD provides **three repositories – frontend, backend and data**.
The **WBD infra team creates the AWS resources with its own IaC and pipelines** from
`aws_resource_list_6.xlsx`. DevOps owns the architecture, the resource list, the client inputs, the
integration of the three repositories' pipelines with the created resources and the end-to-end
verification. The Terraform in this repo is the reference specification of the list.

---

## 0. How to resume in a new chat

> I'm continuing the WBD MMM DevOps project, v6 architecture. Read `Project_memory.md` (root) and
> `docs/requirements/PROJECT_CONTEXT_6.md` first, then `docs/requirements/devops_plan_6.txt`. GitHub
> `Yashwanth-wbd/wbd-aws-devops`. Follow the rules in section 3 of `Project_memory.md`.
> Today I want to: <e.g. "implement v6 Step 8 (internal ALB)">.

---

## 1. Documents

| File (`docs/requirements/`) | What it is |
|---|---|
| `WBD_MMM_Architecture_6.pptx` | **Client v6 (final) architecture** – slide 1 "supports auto ML activities", slide 2 "supports optimization and explainable planning" (read with `tools/extract_pptx.py`) |
| `devops_plan_6.txt` | v6 step-by-step build prompt (Steps 0–16); section A = change summary vs v5; **(v6)** marks every step that changes the built code |
| `aws_resource_list_6.xlsx` | Complete v6 resource list (220 rows, 20 layers) in the v5 layout: `README`, `all_resources` with dev / staging / prod values, sheets `dev` / `staging` / `prod` with real names, `architecture_flow`, `alarms_and_events`, `outside_aws`, `summary`; filter columns **Release**, **Scope** and **Change vs v5** (New 10 / Changed 26 / Same); sheets `v6_changes` and `removed_vs_v5` (12) |
| `wbd_mmm_ecs_final_6.docx` | v6 design document (what changed vs v5, target platform, flows, environments, impact on the v5 code, stages, risks, resource summary, questions with the proposed default) |
| `devops_6_client_question.xlsx` | Complete v6 client questions in the v5 layout: `client_inputs` (110, in 23 sections by layer of `aws_resource_list_6.xlsx`; yellow dev / staging / prod value columns) + `decisions_to_confirm` (38, proposed default until WBD answers) |
| `tools/build_v6.py` | Generates the three v6 xlsx / docx files (`uv run --no-project --with openpyxl --with python-docx python tools\build_v6.py .`) |
| `*_5.*`, `WBD_MMM_Architecture_5.pptx` | v5 inputs (what the current code implements) |

---

## 2. v6 architecture in one page

**Slide 1 – auto ML activities (unchanged from v5):** EventBridge → Step Functions (schedule / manual /
app-triggered, wait / retry) → "Lambda Functions – Export Trigger" → Databricks API connector →
Databricks source catalog export → raw data in S3 (3+ years) → "AWS Glue + Data Catalog (Lineage)":
Bronze → Silver → Gold on Delta Lake (S3) → Glue exports: Gold → training data and Gold → "Lambda
Functions – Results/data publisher" → RDS PostgreSQL → SageMaker training → evaluation → registration →
SageMaker Registry + S3 (approved models, curves, lineage, drift monitoring). Model predictions, lift &
evaluation → results/data publisher → RDS.

**Slide 2 – optimization and explainable planning (changed):** Planner on the WBD network →
**"VPC . Internal ALB + Private App/Data Subnets"** ("ALB / HTTPS"; reached through the WBD network – Transit
Gateway assumed, not drawn) → Okta (authentication + RBAC, IAM Identity Center) → **"One ECS cluster on AWS
Fargate"**: ECS UI (web + QA dashboard, user file upload to S3) ↔ ECS API (FastAPI + LangGraph tools,
explanation tool by default for every run) ↔ RDS. API → SQS → dispatcher Lambda → Step Functions → ECS
inference & optimization task → S3 outputs → results publisher → RDS. **GenAI ("Not part of R1"): API →
"Amazon Runtime VPC Endpoint" → "Amazon Bedrock" (Anthropic Models (Default), Open AI Models (Optional),
Google Models (Optional)) with "Amazon Bedrock Guardrails".** No Route 53 / WAF / API Gateway on the slide.

**Both slides (unchanged):** platform control pane, "AWS IAM" on every integration, "KMS" on every data
store, "Environment level component" (Secrets Manager, VPC routes, CloudWatch, CloudTrail), security /
logging bands.

---

## 3. Change map (v5 built → v6)

| v5 (built) | v6 | Type |
|---|---|---|
| Internet-facing ALB in the public subnets; Route 53 public record; ACM certificate | Internal ALB in the private app subnets; internal name in WBD DNS (or Route 53 private hosted zone + inbound resolver); ACM or WBD private CA certificate | Changed |
| Transit Gateway attachment optional | Required – the only path for planners to the app (assumed; WBD may name another path) | Changed |
| WAF web ACL + logging required | Optional – only if WBD Security requires it | Changed |
| Okta at the public ALB | Okta at the internal ALB; ALB → Okta through NAT | Changed |
| NAT egress: Databricks, Okta, packages, LLM providers | Databricks, Okta, packages – no LLM providers | Changed |
| ECS cluster | "One ECS cluster" | Confirmed |
| API → private API Gateway (`execute-api` endpoint) → proxy Lambda → OpenAI / Anthropic / Google (keys in `llm/*`) | API → `bedrock-runtime` endpoint → Amazon Bedrock Converse (Anthropic default; OpenAI / Google optional) | Changed |
| Guardrail via `ApplyGuardrail` in the proxy | `guardrailConfig` on every call + IAM condition `bedrock:GuardrailIdentifier` | Changed |
| — | Bedrock model access, Bedrock tokens / requests per minute quota, SSM `genai/model_id` + `genai/guardrail`, optional application inference profiles per BU, optional model invocation logging | New |
| LLM gateway alarms (4xx / 5xx / p95) | Bedrock alarms (invocation errors / throttles / latency p95) | Changed |
| LLM gateway, proxy Lambda, `llm/*` secrets, `execute-api` endpoint, `genai` SG | — | Removed |
| One GitHub repo for infra + apps | Frontend, backend and data repositories (WBD); infra by WBD IaC | Changed (delivery) |
| Everything else (slide 1, data platform, optimization engine, RDS, backup, CloudTrail data events) | same | Kept |

---

## 4. Impact on the current code (module by module)

| Path | v6 action |
|---|---|
| `modules/alb` | Variable `internal` (true) + `subnet_ids` (private app); no public subnets; imported / private CA certificate allowed |
| `modules/network` | TGW attachment + WBD routes required; `alb` SG from `alb_ingress_cidrs` (WBD ranges); drop `execute-api` endpoint and `genai` SG; optional private hosted zone + inbound resolver endpoint |
| `modules/llm-gateway` | Delete |
| `modules/monitoring` | `genai` dashboard on `AWS/Bedrock`; subscription filters without LLM log groups |
| `environments/*/frontdoor.tf` | Internal ALB in app subnets; `module "waf"` behind `enable_waf` (false); DNS record in a private zone or WBD DNS only |
| `environments/*/genai.tf` | Remove `module "llm_gateway"`; API role Bedrock policy (Converse / InvokeModel on approved model + profile ARNs, condition `bedrock:GuardrailIdentifier`, `ApplyGuardrail`); SSM `genai/model_id`, `genai/guardrail`; optional inference profiles + invocation logging; Bedrock alarms; `genai_interface_endpoints = ["bedrock-runtime"]` |
| `environments/*/main.tf` | Remove `llm/*` secrets; `uploads` CORS = internal app URL |
| `environments/*/ecs.tf` | API env `BEDROCK_MODEL_ID` / `BEDROCK_GUARDRAIL_ID` / `BEDROCK_GUARDRAIL_VERSION` instead of `LLM_GATEWAY_URL` |
| `environments/*/variables.tf`, `terraform.tfvars` | `enable_transit_gateway = true`; `alb_ingress_cidrs` = WBD ranges; add `enable_waf`, `enable_private_hosted_zone`, `genai_model_ids`, `enable_bedrock_invocation_logging`; remove `llm_providers`, `genai_reserved_concurrency`, `manage_apigw_account_logging_role` |
| `environments/*/outputs.tf`, `tests/mock-plan.tftest.hcl` | New expected counts |
| `docs/` + runbooks | 05, 06, 12 front door; `genai.md` (Bedrock); `okta-outage` (NAT egress); `security-incident` (no public entry); diagrams |
| Unchanged | bootstrap, kms, permission-boundary (plus Bedrock actions), iam-oidc (trust subjects of the three repos), ecr, ecs-cluster, ecs-service, rds, run-queue, step-functions, lambda-function, databricks-export, databricks-access, glue, sagemaker, backup, bedrock-guardrails, log-bucket, log-shipping, budgets, s3-bucket |

---

## 5. Proposed implementation order (after the user verifies this plan)

1. Front door: `modules/alb` internal, `modules/network` (TGW required, `alb` SG, optional private zone / inbound resolver), `frontdoor.tf` (WAF optional, DNS), `uploads` CORS (Steps 2, 4, 6, 8).
2. GenAI on Bedrock: delete `modules/llm-gateway`, remove `llm/*`, `execute-api`, `genai` SG; Bedrock IAM + SSM + API env + alarms (Steps 2, 4, 5, 15).
3. Monitoring and dashboards (Step 10); OIDC trust for the three repositories (Steps 3, 12).
4. Docs, runbooks, mock-plan expectations, `Project_memory.md`; regenerate the `_6` files with the build status.

Each step: `terraform fmt/validate`, `validate-modules.ps1`, `sync-environments.ps1 -Check`,
`mock-plan.ps1`, tflint, Checkov, actionlint, secret scan.

---

## 6. Open questions and the proposed default

| # | Question | Proposed default [ASM] (to confirm with WBD) |
|---|---|---|
| 1 | **How do planners reach the internal ALB?** | WBD network (offices, VPN, VDI) → Transit Gateway → app subnets; ALB SG allows only the WBD CIDRs |
| 2 | Internal DNS name and certificate? | CNAME in WBD internal DNS; ACM DNS-validated certificate if under a public WBD domain, else WBD private CA |
| 3 | WAF on the internal ALB? | Not at go-live; optional if WBD Security requires it |
| 4 | Okta sign-in from an internal ALB? | `authenticate-oidc` stays; ALB reaches Okta through NAT |
| 5 | **LLM access on Bedrock** | API calls Bedrock Converse through the `bedrock-runtime` endpoint; no gateway, no proxy, no API keys |
| 6 | Models? | Anthropic Claude (default) on Bedrock; OpenAI / Google only after approval |
| 7 | Guardrail enforcement | `guardrailConfig` on every call + IAM condition `bedrock:GuardrailIdentifier` |
| 8 | Cross-region inference profile? | US profile where the model needs it; SCP allows the profile regions |
| 9 | Bedrock invocation logging? | Metadata only; text logging only if Privacy approves |
| 10 | Who creates the resources? | WBD Infra with its own IaC from `aws_resource_list_6.xlsx`; our Terraform is the reference |
| 11 | What do the three repositories deploy? | Images, ECS task revisions, Lambda code, Glue scripts – no infrastructure |
| 12 | Still open from v5 | Gold reference table sizes, lineage UI (no), CloudTrail data events in the org trail, Identity Center with Okta, RDS sizes, Fargate / Glue quotas |

Answered by v6 (removed from the question list): app reachable from the internet (no – internal ALB);
provider API keys `llm/*` (no – Bedrock); one or several ECS clusters (one).

---

## 7. Session history

1. 17 Nov 2026: final client deck `WBD_MMM_Architecture_6.pptx` added to `docs/requirements/` and compared
   with `WBD_MMM_Architecture_5.pptx` (slide text + images); v6 documents created (`devops_plan_6.txt`, this
   file, `aws_resource_list_6.xlsx`, `wbd_mmm_ecs_final_6.docx`, `devops_6_client_question.xlsx`, generator
   `tools/build_v6.py`). No platform code changed; not committed.

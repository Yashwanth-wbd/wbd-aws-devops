"""Build WBD_MMM_v6_Infra_Build_Guide.docx - the v6 architecture, flows, AWS services (what and why) and the
order in which the WBD infrastructure team creates them. Written for the case where EY has no AWS access and
WBD Infra creates every resource with its own tooling. No Terraform content.

Source: WBD_MMM_Architecture_6.pptx, aws_resource_list_6.xlsx, devops_6_client_question.xlsx.

    uv run --no-project --with python-docx python .\\build_v6_infra_guide.py <requirements folder>
"""
import sys
from pathlib import Path

import docx
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

OUT = "WBD_MMM_v6_Infra_Build_Guide.docx"
NAVY = RGBColor(0x1F, 0x3A, 0x5F)
GREY = RGBColor(0x55, 0x55, 0x55)

d = docx.Document()
for s in d.sections:
    s.left_margin = s.right_margin = Cm(2)
    s.top_margin = s.bottom_margin = Cm(1.8)
d.styles["Normal"].font.name = "Calibri"
d.styles["Normal"].font.size = Pt(10.5)


def shade(cell, fill):
    pr = cell._tc.get_or_add_tcPr()
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear")
    sh.set(qn("w:color"), "auto")
    sh.set(qn("w:fill"), fill)
    pr.append(sh)


def h(text, level=1):
    p = d.add_heading(text, level=level)
    for r in p.runs:
        r.font.color.rgb = NAVY


def para(text, bold=None):
    p = d.add_paragraph()
    if bold:
        p.add_run(bold).bold = True
    p.add_run(text)
    p.paragraph_format.space_after = Pt(4)
    return p


def bullets(items, style="List Bullet"):
    for it in items:
        p = d.add_paragraph(style=style)
        if isinstance(it, tuple):
            p.add_run(it[0]).bold = True
            p.add_run(it[1])
        else:
            p.add_run(it)
        p.paragraph_format.space_after = Pt(2)


def steps(items):
    bullets(items, "List Number")


def table(headers, rows, widths=None, font=9):
    t = d.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, hd in enumerate(headers):
        c = t.rows[0].cells[i]
        c.text = ""
        r = c.paragraphs[0].add_run(hd)
        r.bold = True
        r.font.size = Pt(font)
        r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
        shade(c, "1F3A5F")
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ""
            cells[i].paragraphs[0].add_run(str(v)).font.size = Pt(font)
    if widths:
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
    d.add_paragraph().paragraph_format.space_after = Pt(2)


def diagram(text):
    p = d.add_paragraph()
    r = p.add_run(text)
    r.font.name = "Consolas"
    r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
    r.font.size = Pt(8)
    pPr = p._p.get_or_add_pPr()
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear")
    sh.set(qn("w:fill"), "F2F4F7")
    pPr.append(sh)


def callout(label, text):
    t = d.add_table(rows=1, cols=1)
    t.style = "Table Grid"
    c = t.rows[0].cells[0]
    shade(c, "FFF4D6")
    c.text = ""
    p = c.paragraphs[0]
    p.add_run(label + " ").bold = True
    p.add_run(text)
    d.add_paragraph().paragraph_format.space_after = Pt(2)


# ================================================================== title
for txt, size, bold in [
    ("WBD Media-Mix Modeling (MMM) Platform", 22, True),
    ("v6 architecture, flows and AWS resources - build guide for the WBD infrastructure team", 13, False),
]:
    p = d.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(txt)
    r.bold = bold
    r.font.size = Pt(size)
    r.font.color.rgb = NAVY if bold else None
p = d.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("Sources: WBD_MMM_Architecture_6.pptx, aws_resource_list_6.xlsx, devops_6_client_question.xlsx - 17 Nov 2026")
r.italic = True
r.font.size = Pt(9)
r.font.color.rgb = GREY

h("How to use this document")
para("The EY team does not have access to the WBD AWS accounts. The WBD infrastructure team therefore creates every AWS "
     "resource of the MMM platform in its own accounts, with its own tooling (CloudFormation, Terraform or the console). "
     "This document gives the infra team everything needed to do that with confidence:")
bullets([
    ("Sections 1-3: ", "what the platform does, what the v6 architecture looks like and what changed."),
    ("Section 4: ", "the end-to-end flows - what happens, in which order, through which AWS services."),
    ("Section 5: ", "every AWS service in the resource list and WHY it is used (and what it is not used for)."),
    ("Section 6: ", "WHAT TO CREATE FIRST - the build order in phases, with dependencies, owners, a check per phase and "
     "the values to hand back to EY."),
    ("Sections 7-9: ", "the network and security rules to apply, the inputs needed from other WBD teams, and the questions "
     "the infra team is likely to ask."),
])
para("The resource list aws_resource_list_6.xlsx is the detailed specification (214 rows: name per environment, size, "
     "configuration, dependency, owner). This document explains it; 'row N' refers to its all_resources sheet and 'layer NN' "
     "to its Layer column. EY can additionally share the exact IAM policy documents, bucket policies and key policies of its "
     "reference implementation for any resource on request.")

# ================================================================== 1
h("1. The platform in brief")
para("WBD media planners decide how to spend marketing budgets across channels for three business units (streaming, "
     "theatrical, US networks). The MMM platform replaces a third-party tool:")
bullets([
    ("It learns (slide 1 - auto ML): ", "every week, or on request, it pulls 3+ years of history from WBD Databricks into AWS, "
     "prepares it in a Bronze / Silver / Gold lakehouse, trains one media-mix model per business unit, has a WBD approver "
     "approve it, and checks it for drift every day."),
    ("It plans (slide 2 - optimization and explainable planning): ", "planners use an internal web application to upload an "
     "inventory or future titles, choose an objective, run optimizations and forecasts, compare and approve scenarios and "
     "export them. 50-150 planners work at the same time in planning season."),
    ("It explains (Release 2): ", "each run receives a plain-language explanation from Amazon Bedrock (Anthropic models by "
     "default) with Bedrock Guardrails. This is marked 'Not part of R1' on the slide."),
])
table(
    ["Item", "Value"],
    [
        ("AWS accounts", "wbd-mmm-dev, wbd-mmm-stage, wbd-mmm-prod (one per environment; name codes dev / stg / prd)"),
        ("Region", "us-east-1; DR region us-west-2 only if WBD approves"),
        ("Business units", "streaming, theatrical, usnetworks"),
        ("Application stack", "React + TypeScript (UI), Python FastAPI + LangGraph (API), scikit-learn / XGBoost / SciPy (models, solver), PostgreSQL, Databricks / S3"),
        ("Code", "Three WBD repositories - frontend, backend, data. Their pipelines deploy images and code only; they never create infrastructure."),
        ("Release 1 (go-live)", "Everything except GenAI. Release 2 = GenAI on Amazon Bedrock after WBD Responsible AI approval."),
    ],
    widths=[4, 13],
)

# ================================================================== 2
h("2. The v6 architecture")
h("2.1 What changed in v6", 2)
table(
    ["v6 requirement", "Consequence for the build"],
    [
        ("DNS/WAF + Route 53 removed (internal application)", "Do not create AWS WAF or any Route 53 hosted zone, record or resolver. The app name is a CNAME in WBD internal DNS."),
        ("Private access only, no public entry", "The Application Load Balancer is INTERNAL (private subnets, private IPs). It is reachable only from the WBD network through the Transit Gateway; its security group allows WBD CIDRs only."),
        ("User authenticates with Okta first, then the ALB routes", "The HTTPS listener's first action is Okta OIDC authentication. Nothing reaches the UI / API before sign-in."),
        ("ECS inference & optimization - clusters or services?", "ONE ECS cluster per environment. ui and api are services; each optimization run is one Fargate task running Model Summarizer -> Optimizer -> Simulation in one container."),
        ("Amazon API Gateway removed", "No API Gateway, no proxy Lambda, no execute-api endpoint."),
        ("Bedrock with Anthropic default; OpenAI / Google optional", "The API calls Amazon Bedrock directly via the bedrock-runtime VPC endpoint with IAM (no provider API keys). OpenAI / Google models on Bedrock only for experiments, if approved."),
    ],
    widths=[6, 11],
)
h("2.2 Picture of one environment", 2)
diagram(
    " WBD network (office / VPN / VDI)            Outside AWS: Okta, WBD Databricks, WBD DNS, (Splunk)\n"
    "        |  WBD internal DNS: mmm.<internal domain> -> internal ALB\n"
    "        |  WBD Transit Gateway\n"
    " =======|=============== AWS account wbd-mmm-<env>, us-east-1 =================================\n"
    "  VPC (/19)\n"
    "   PUBLIC subnets ........ NAT gateways only (outbound to Okta + Databricks). Nothing inbound.\n"
    "   PRIVATE APP subnets ... Internal ALB  -- Okta sign-in first --> ECS service ui  (web)\n"
    "                                                              --> ECS service api (FastAPI)\n"
    "                           ONE ECS cluster: ui, api, migrate, platform-check, optimizer task/run\n"
    "                           Lambdas: run dispatcher, results/data publisher, Databricks export\n"
    "                           Glue job ENIs, SageMaker job ENIs\n"
    "   PRIVATE DATA subnets .. RDS Proxy -> RDS PostgreSQL (Multi-AZ in staging / prod)\n"
    "   PRIVATE ENDPOINT subnets  interface endpoints: ECR, STS, KMS, Logs, Monitoring, Secrets Manager,\n"
    "                             SSM, SQS, Step Functions, X-Ray, SageMaker API, Glue, bedrock-runtime\n"
    "  Regional services used privately: S3 (10 buckets), SQS, Step Functions, EventBridge, Glue,\n"
    "  SageMaker (training, Model Registry), Amazon Bedrock + Guardrails, CloudWatch, SNS, Backup\n"
    " =============================================================================================="
)
h("2.3 The two slides in one line each", 2)
bullets([
    ("Slide 1: ", "EventBridge -> Step Functions model-refresh -> Export Trigger Lambda -> Databricks export -> S3 landing -> "
     "Glue Bronze -> Silver -> Gold (Delta Lake) -> Glue exports -> publisher Lambda (reference data -> RDS) -> SageMaker "
     "training -> evaluation -> Model Registry (approval) -> lineage -> publisher Lambda (model results -> RDS); daily drift monitor."),
    ("Slide 2: ", "Planner -> internal ALB (Okta first) -> ECS ui / api -> S3 uploads -> SQS -> dispatcher Lambda -> Step "
     "Functions -> ECS inference & optimization task -> S3 results -> publisher Lambda -> RDS; Release 2: api -> Bedrock."),
    ("Control plane on both slides: ", "IAM role per integration, KMS on every store, Secrets Manager, security groups, VPC "
     "routes, CloudWatch and CloudTrail 'enabled across all components', code repositories / CI/CD."),
])

# ================================================================== 3
h("3. Working model: who does what")
table(
    ["Party", "Responsibility"],
    [
        ("WBD Infra (this team)", "Creates and owns all AWS resources of aws_resource_list_6.xlsx in dev, then staging, then prod; changes infrastructure later on request."),
        ("WBD Cloud Platform / Security", "Accounts and baseline (SCPs, CloudTrail, GuardDuty, Security Hub, Config, Identity Center), quotas, Bedrock model access, key and IAM standards."),
        ("WBD Network / DNS / PKI", "Transit Gateway, CIDRs, egress, internal DNS name, certificate."),
        ("WBD Identity", "Okta OIDC app per environment, groups, client secret."),
        ("WBD Databricks admins", "Export jobs, service principal, Unity Catalog storage credential + external location."),
        ("WBD repository owners + app / data teams", "Frontend, backend, data repositories and pipelines; container images, Lambda code, Glue scripts, DB migrations."),
        ("EY DevOps", "Specifications (this document, the resource list, policy documents on request), pipeline definitions, runbooks, verification of each phase together with WBD Infra (screen share or read-only access), support during the first deploys."),
    ],
    widths=[5, 12],
)
callout("Handback:", "after each phase, WBD Infra fills the 'ARN / ID' column of the dev / staging / prod sheet of the "
        "resource list (or shares the IaC outputs). EY needs these values for the pipeline variables of the three repositories "
        "and for the application configuration. Section 6 lists exactly which values per phase.")

# ================================================================== 4
h("4. The end-to-end flows")
h("4.1 Planner access - private entry, Okta first (S2-1)", 2)
steps([
    "The planner is on the WBD network and opens https://mmm.<internal domain> (or the Okta dashboard tile).",
    "WBD internal DNS resolves the CNAME to the internal ALB; traffic enters the VPC through the Transit Gateway.",
    "The ALB security group accepts 443 (80 only redirects) from WBD CIDRs.",
    "The listener terminates TLS and runs authenticate-oidc: without an Okta session the browser is sent to Okta (SSO + MFA), "
    "comes back to /oauth2/idpresponse, and the ALB calls Okta's token / user-info endpoints outbound through NAT.",
    "Only then is the request forwarded: /api/* to the api target group, everything else to ui (port 8080). /api/health is "
    "open for health checks. The ALB passes a signed identity header with the Okta groups; the API applies RBAC and PostgreSQL "
    "row-level security per business unit.",
])
h("4.2 Optimization or forecast run (S2-2 to S2-10)", 2)
steps([
    "The planner works in the UI; the API reads / writes plans, runs and allocations in RDS through RDS Proxy.",
    "Upload: the API returns a presigned URL; the browser uploads the inventory / future-titles file straight to the S3 uploads bucket.",
    "Queue: the API stores the run as QUEUED and sends a message to SQS optimization-requests (DLQ after 10 failures).",
    "Dispatch: the dispatcher Lambda starts a Step Functions execution while fewer than max_concurrent_runs (5 / 20 / 50) run.",
    "Run: Step Functions starts ONE ECS Fargate task in the same cluster: Model Summarizer -> Optimizer -> Simulation. It reads "
    "the upload, the approved model (SageMaker Model Registry) and approved response curves (S3 models), and writes the full "
    "run evidence to S3 results. It has no database access.",
    "Publish: Step Functions invokes the results publisher Lambda, which writes the results to RDS; the UI shows them.",
    "Approve / export: approved scenarios go to the approved-worm bucket (Object Lock, 7 years); Excel exports to exports (30 days).",
])
h("4.3 GenAI explanation - Release 2 (S2-9)", 2)
steps([
    "After a run the API's LangGraph explanation tool reads model ID, guardrail and BU token quota from SSM Parameter Store.",
    "It calls the Bedrock Converse API with its task role through the bedrock-runtime VPC endpoint (no internet, no API key).",
    "Bedrock Guardrails check the prompt and the answer (prompt attack, content, PII, denied topics, grounding, relevance).",
    "IAM allows only the approved models and only with the MMM guardrail; the endpoint policy allows only this account.",
])
h("4.4 Model refresh (S1-1 to S1-13)", 2)
steps([
    "Trigger: weekly schedule per BU (EventBridge Scheduler), on-demand event mmm.refresh, or drift -> Step Functions model-refresh.",
    "Export Trigger Lambda gets an OAuth token (Databricks service principal from Secrets Manager) and starts / polls the "
    "BU's Databricks export job (via NAT or PrivateLink).",
    "Databricks writes raw Parquet into the S3 landing bucket through a write-only IAM role (Unity Catalog external location).",
    "Glue jobs Bronze -> Silver (Data Quality rules; failure stops the refresh) -> Gold (adstock, saturation), Delta Lake on S3, Glue Data Catalog.",
    "Glue exports: an immutable training snapshot (training-data bucket, Object Lock) and Gold reference tables as Parquet (lakehouse/rds-export/).",
    "Publisher Lambda loads the reference data into RDS (Glue never connects to the database).",
    "SageMaker training (in the VPC) -> evaluation (baseline -> channel lift -> title adjustment) -> Model Registry "
    "(PendingManualApproval; a named WBD approver approves; approved curves published to S3).",
    "Lineage is recorded (export run -> Glue tables -> snapshot -> training job -> model version); publisher writes predictions, "
    "lift and evaluation to RDS.",
])
h("4.5 Daily drift monitoring (S1-12)", 2)
para("A daily schedule per BU runs model-monitor: same export + Glue layers, Glue export-monitor, a SageMaker drift job and the "
     "ModelDrift metric. Above 0.2 an alarm fires (alert only unless WBD enables automatic refresh).")
h("4.6 Releases (P-3)", 2)
para("The three repository pipelines sign in with OIDC (no keys), push images to ECR, run the DB migration task, register new "
     "task-definition revisions, update the ECS services, publish Lambda versions and upload Glue scripts. Build once in dev, "
     "promote the same image digest to staging and prod (prod: WBD approver + CAB ticket). The post-deploy smoke test calls the "
     "internal ALB, so it needs a pipeline runner inside the WBD network or VPC.")

# ================================================================== 5
h("5. Every AWS service - what it is used for and why")
para("Grouped by the layers of the resource list. 'Why' explains the choice; 'Not used for' prevents common misreadings.")


def svc_table(rows):
    table(["Service / resource", "What it does here", "Why this choice"], rows, widths=[3.6, 6.4, 7], font=8.5)


h("Layer 01 - Account baseline (verify, mostly WBD-owned)", 2)
svc_table([
    ("AWS Organizations, SCPs", "Separate account per environment; service / region guardrails", "Blast-radius isolation and separate billing per environment; SCPs must allow ECS, Lambda, Step Functions, SQS, Glue, SageMaker, Bedrock, Firehose, Backup, EventBridge Scheduler (+ Bedrock profile regions in R2)"),
    ("IAM Identity Center", "Engineer access via Okta (permission sets ReadOnly, Developer, DevOps, Security, BreakGlass)", "No IAM users or long-lived keys; one identity source (Okta) for people"),
    ("CloudTrail, GuardDuty, Security Hub, Config, Inspector, Access Analyzer", "Audit, threat detection, compliance, image scanning", "WBD baseline; the platform raises alerts from GuardDuty (severity >= 7) and break-glass use"),
    ("S3 Block Public Access, EBS default encryption", "Account-level safety settings", "Nothing in this platform is public"),
    ("Service Quotas", "Fargate vCPU (>= 40 / 120 / 450), Glue runs (>= 20), SageMaker instances (>= 3), Bedrock tokens (prod >= 200k / min)", "Default quotas are too low for 50 parallel optimization runs and 3 BUs refreshing at once"),
    ("Bedrock model access (R2)", "Enables the Anthropic model (first-time-use form); OpenAI / Google only if approved", "Bedrock models must be enabled per account before they can be invoked"),
])
h("Layers 02-04 - State, encryption, IAM and CI/CD access", 2)
svc_table([
    ("S3 + KMS for Terraform state (optional)", "Only if WBD uses Terraform", "Not needed if WBD uses another tool"),
    ("AWS KMS customer-managed keys", "Keys per purpose: s3, rds, logs, secrets, ecr, sqs, sagemaker, alerts, backup (+ backup-dr), genai; plus s3-<bu> per business unit", "Slides draw KMS on every store. Separate keys limit who can decrypt what; per-BU keys isolate each business unit's data in landing / lakehouse / training-data"),
    ("IAM permission boundary", "Attached to every MMM role", "Caps any role even if a policy is too broad: no IAM users / keys, approved regions only, cannot disable security services"),
    ("IAM OIDC provider (GitHub or WBD CI tool)", "Keyless login for the three repository pipelines", "No stored AWS keys in CI"),
    ("Pipeline roles gha-ecr-push, gha-deploy, gha-model-eval, gha-model-approve (gha-plan / gha-apply optional)", "Push images, deploy revisions, model governance", "Least privilege per pipeline task; trust limited to WBD repos + environment; plan / apply only if WBD runs Terraform from a pipeline"),
    ("AWS Budgets, Cost Anomaly Detection", "Monthly budget (3k / 6k / 15k USD proposed) and daily anomaly alerts", "Early warning on Fargate, Glue, SageMaker and Bedrock spend"),
])
h("Layers 05-06 - Networking and security groups", 2)
svc_table([
    ("VPC with 4 subnet tiers", "public (NAT only), private app, private data, private endpoint; 2 AZs dev, 3 AZs staging / prod", "Separates what can reach what; the database tier has no internet route"),
    ("Transit Gateway attachment + routes", "WBD network <-> VPC", "THE ONLY ENTRY to the app (v6: no public entry). Required in all environments"),
    ("Internet gateway + NAT gateways", "Outbound only: Okta (ALB sign-in), Databricks API, package indexes", "The ALB's Okta integration and the Databricks API need HTTPS egress; can be replaced by WBD central egress"),
    ("S3 / DynamoDB gateway endpoints", "Private, free S3 access", "Large data volumes (Glue, SageMaker, uploads) without NAT cost"),
    ("Interface endpoints (13 core + glue + bedrock-runtime)", "Private access to AWS APIs", "Tasks and jobs in private subnets reach ECR, STS, KMS, Logs, SQS, Step Functions, Secrets Manager, SSM, SageMaker, Glue and Bedrock without internet"),
    ("VPC flow logs", "Network records for investigations", "Security baseline"),
    ("Databricks PrivateLink (optional)", "Private path to the Databricks workspace", "Only if WBD does not want Databricks calls through NAT"),
    ("13 security groups", "One per component (alb, ui, api, data-clients, rds-proxy, rds, optimizer, lambda, tasks, databricks-export, glue, sagemaker, endpoints)", "Least privilege between components; see section 7.2"),
])
h("Layers 07-09 - Images, secrets / parameters, storage", 2)
svc_table([
    ("Amazon ECR (mmm/api, mmm/ui, mmm/optimizer, mmm/sagemaker-training)", "Container images per account", "Fargate and SageMaker pull privately via endpoints; immutable tags and enhanced scanning"),
    ("Secrets Manager (mmm/<env>/...)", "DB users, Okta ALB client secret, Databricks service principal, optional Splunk / vendor keys", "Secret values never in code, images, pipelines or email; owners enter them; RDS manages its admin password itself"),
    ("SSM Parameter Store (/mmm/<env>/...)", "Non-secret settings and release pointers: max_concurrent_runs, optimizer task definition, training image, Okta issuer, Databricks host / job IDs, GenAI switch / model / guardrail / quotas", "Change behaviour (e.g. pause runs, switch model) without redeploying"),
    ("S3 buckets (10)", "logs, landing, lakehouse, training-data, glue-assets, models, uploads, results, approved-worm, exports", "Cheap durable storage per purpose with its own policy, lifecycle and key; Object Lock where data must be immutable (training-data, approved-worm - must be enabled AT CREATION)"),
])
h("Layers 10-12 - Database, ECS, internal entry", 2)
svc_table([
    ("RDS for PostgreSQL 16 (+ subnet / parameter group)", "System of record: plans, runs, allocations, Gold reference data, model results; row-level security per BU", "Prescribed stack; relational data with RLS; Multi-AZ in staging / prod"),
    ("RDS Proxy", "Connection pooling, TLS, IAM auth for api and publisher", "Many API tasks and Lambda invocations would otherwise exhaust connections"),
    ("ECS cluster on Fargate (one)", "Services ui and api; one-off tasks migrate, platform-check; optimizer task per run", "Serverless containers, no EC2 to patch; one cluster is enough (v6 decision) - isolation comes from task roles, SGs and scaling"),
    ("Application Auto Scaling", "CPU target tracking 60 % for api and ui", "Handles 50-150 planners in planning season"),
    ("Cloud Map (Service Connect namespace)", "Service names inside the cluster", "Service-to-service calls without hard-coded addresses"),
    ("ACM certificate", "TLS for the internal app name", "ACM DNS-validated if the name is under a public WBD domain, else a WBD private-CA certificate"),
    ("Internal Application Load Balancer", "HTTPS entry, Okta OIDC first, /api/* -> api, /* -> ui", "Native Okta (OIDC) authentication before any request reaches the app; internal scheme = no public entry"),
    ("Okta OIDC app (outside AWS)", "Authentication, MFA, groups for RBAC", "WBD enterprise identity provider"),
])
h("Layer 13 - Optimization engine", 2)
svc_table([
    ("SQS queue + DLQ", "Holds run requests", "Absorbs planning-season bursts; failed requests are kept, not lost"),
    ("Lambda run dispatcher", "Starts runs while running < max_concurrent_runs", "Caps concurrency so runs fit the Fargate quota and the database"),
    ("Step Functions state machine optimization", "Runs the ECS task (.sync), then the publisher, with retries / timeouts", "Visual, audited orchestration with built-in retry; no custom scheduler code"),
    ("ECS task definition optimizer (one task per run)", "Model Summarizer -> Optimizer -> Simulation", "Each run isolated in its own container (4 vCPU / 16 GB, prod 8 / 32); scales to zero"),
    ("Lambda results/data publisher", "Writes run results, Gold reference data and model results to RDS", "Single, small component with database write access; the optimizer and Glue stay without DB access"),
])
h("Layers 14-17 - Data platform (model refresh)", 2)
svc_table([
    ("IAM role for Databricks Unity Catalog (write-only)", "Lets the Databricks export job write raw files to landing", "Databricks can write only to raw/databricks/* and cannot read anything else"),
    ("Lambda Export Trigger (Databricks API connector)", "Starts and polls the Databricks export job", "Databricks stays the source; AWS controls when and what is exported"),
    ("AWS Glue 5.0 jobs + Data Catalog + Data Quality", "Bronze / Silver / Gold Delta tables, exports, validation rules, lineage table properties", "Serverless Spark; Delta Lake on S3 as drawn; Data Quality stops bad data before training"),
    ("Amazon SageMaker (training, processing, Model Registry, ML Lineage)", "Train, evaluate, register per BU; drift jobs; lineage", "Managed ML jobs in the VPC; registry gives versioning and human approval"),
    ("Step Functions model-refresh and model-monitor", "Orchestrate the refresh and the daily drift check", "Wait / retry / error handling across Lambda, Glue and SageMaker without servers"),
    ("EventBridge Scheduler + EventBridge rules", "Weekly refresh, daily drift, on-demand mmm.refresh, model state alerts", "Cron in a timezone, plus event-driven triggers"),
    ("Amazon DataZone (optional)", "Visual lineage graph", "Only if WBD wants a lineage UI"),
])
h("Layer 18 - GenAI on Amazon Bedrock (Release 2)", 2)
svc_table([
    ("Amazon Bedrock foundation model - Anthropic (default)", "Writes the explanation of each run", "Slide 2 'Anthropic Models (Default)'; runs inside AWS, IAM access, no external API key"),
    ("OpenAI / Google models on Bedrock (optional)", "Experimentation only", "Slide 2 marks them optional; prod Anthropic only unless WBD approves"),
    ("Bedrock Guardrails (+ version)", "Filters prompts and answers", "'Privacy & GenAI Guardrails'; enforced by IAM condition so no call can skip it"),
    ("bedrock-runtime VPC endpoint", "Private path API -> Bedrock", "'Amazon Runtime VPC Endpoint' on the slide; replaces API Gateway"),
    ("Application inference profiles per BU (optional)", "Bedrock cost and tokens per BU", "Cost reporting per business unit"),
    ("Model invocation logging (optional)", "Audit of model calls", "Metadata only unless WBD Privacy approves text logging"),
])
h("Layers 19-20 - Monitoring, logging, backup", 2)
svc_table([
    ("CloudWatch logs, metrics, alarms (sheet alarms_and_events), 8 dashboards, Container Insights", "Observability of every component", "'CloudWatch - to be enabled across all components'"),
    ("EventBridge alert rules", "GuardDuty high, break-glass, ECS deploy / start failures, backup, Glue, DQ, model state", "Event-based problems that are not metrics"),
    ("SNS topic mmm-<env>-alerts", "Delivers every alarm to on-call", "One place to subscribe email / paging"),
    ("CloudWatch Logs data protection policy", "Masks personal data in logs", "Privacy"),
    ("Kinesis Data Firehose -> Splunk (optional)", "Ships logs to WBD Splunk", "Only if WBD requires Splunk"),
    ("AWS Backup (vault, daily plan, tag selection, optional DR copy)", "Daily backups of RDS and data buckets", "Central, policy-based backup with vault lock in prod"),
])

# ================================================================== 6
h("6. What to create first - build order")
para("Create everything in dev first, verify, then repeat the same order in staging and prod. Each phase only depends on "
     "earlier phases. Release 1 needs phases 0-9; the data platform (phase 10) can follow the core; GenAI (phase 11) only "
     "after WBD approval for Release 2.")
diagram(
    " Phase 0  Inputs & decisions (no AWS resources)\n"
    "   -> 1  Account baseline + quotas\n"
    "   -> 2  KMS keys\n"
    "   -> 3  IAM foundation (permission boundary, OIDC provider, budgets)\n"
    "   -> 4  Network: VPC, subnets, NAT, routes, Transit Gateway, endpoints, security groups\n"
    "   -> 5  ECR, Secrets Manager containers, SSM parameters, S3 buckets, SNS alerts topic\n"
    "   -> 6  Database: RDS PostgreSQL + RDS Proxy, DB users\n"
    "   -> 7  ECS cluster, roles, task definitions, services  +  internal ALB, certificate, Okta, DNS\n"
    "          ==> CHECKPOINT: a planner on the WBD network signs in with Okta and sees the app\n"
    "   -> 8  Optimization engine: SQS, dispatcher, Step Functions, optimizer task, publisher\n"
    "          ==> CHECKPOINT: one optimization run end-to-end\n"
    "   -> 9  Monitoring, alarms, dashboards, backup; pipeline roles for the 3 repositories\n"
    "          ==> RELEASE 1 CORE READY (repeat 1-9 in staging, prod)\n"
    "   -> 10 Data platform: Databricks role + export Lambda, Glue, SageMaker, refresh / drift\n"
    "          ==> CHECKPOINT: one model refresh per BU, model approved\n"
    "   -> 11 Release 2 GenAI: genai key, bedrock-runtime endpoint, guardrail, model access, alarms"
)


def phase(title, why, create, depends, owner, check, handback):
    h(title, 2)
    para(why, bold="Why now: ")
    para("", bold="Create:")
    bullets(create)
    para(depends, bold="Depends on: ")
    para(owner, bold="Owner(s): ")
    para(check, bold="Check before moving on: ")
    para(handback, bold="Hand back to EY: ")


phase("Phase 0 - Inputs and decisions (before any resource)",
      "Several settings cannot be changed later (VPC CIDR, Object Lock, account / region) or block whole phases (Transit Gateway, certificate, Okta).",
      ["Account IDs, region, SCP confirmation (devops_6_client_question.xlsx section 2)",
       "VPC CIDR per environment and AZ IDs; Transit Gateway ID, route table, RAM share; WBD CIDRs allowed to reach the ALB; egress model (NAT or central egress)",
       "Internal app name per environment and certificate approach (ACM DNS-validated or WBD private CA)",
       "Okta: issuer and client per environment (redirect https://<name>/oauth2/idpresponse), group names",
       "Names of the three repositories and the CI/CD tool (for the OIDC trust)",
       "KMS / IAM standards: may MMM keys and roles follow the list, is the permission boundary mandatory",
       "Decisions Q1-Q36 (decisions_to_confirm sheet) at least Q1-Q4, Q13, Q35, Q36"],
      "-", "WBD Cloud Platform, Network, DNS / PKI, Identity, repository owners", "All yellow cells for the environment filled in client_inputs.",
      "The filled client_inputs values.")

phase("Phase 1 - Account baseline and quotas (layer 01)",
      "Quota requests take days; baseline services must exist before workloads.",
      ["Verify: account in the org, SCPs allow the services, Identity Center permission sets, CloudTrail org trail (events to EventBridge), GuardDuty, Security Hub, Config, Inspector ECR scanning, Access Analyzer, S3 Block Public Access, EBS default encryption",
       "Request quotas: Fargate vCPU, Glue concurrent runs / DPUs, SageMaker instances (Bedrock tokens later, Release 2)",
       "Optional: CloudTrail S3 data events for the MMM buckets (after phase 5), Macie"],
      "Phase 0", "WBD Cloud Platform / Security", "Engineers can sign in through Identity Center; quota tickets raised.",
      "Account IDs, Identity Center start URL, quota status.")

phase("Phase 2 - KMS keys (layer 03)",
      "Almost every later resource is encrypted with one of these keys; key policies must name the roles created later, so start with account root + admin and extend.",
      ["Keys s3, rds, logs, secrets, ecr, sqs, alerts, backup (Release 1 core)",
       "Keys sagemaker and s3-streaming / s3-theatrical / s3-usnetworks (data platform - can be created now or in phase 10)",
       "Key genai (Release 2 only); backup-dr in us-west-2 (only if DR approved)",
       "Rotation on; aliases alias/mmm-<env>-<purpose>"],
      "Phase 1", "WBD Infra (+ Security as key admin)", "All aliases exist; rotation enabled.",
      "Key ARNs per alias.")

phase("Phase 3 - IAM foundation and budgets (layer 04)",
      "Every role created later must carry the permission boundary; the OIDC provider is needed for the pipelines.",
      ["Managed policy mmm-<env>-permission-boundary",
       "IAM OIDC identity provider for the CI/CD tool (token.actions.githubusercontent.com if GitHub Actions)",
       "AWS Budget mmm-<env>-monthly, cost anomaly monitor + subscription",
       "Pipeline roles can be created now (trust only) and their permissions completed in phase 9"],
      "Phase 2", "WBD Infra / Security", "Boundary attached to a test role; budget email received.",
      "Permission boundary ARN, OIDC provider ARN.")

phase("Phase 4 - Network and security groups (layers 05, 06)",
      "Everything runs in the VPC; the Transit Gateway is the only way planners reach the app.",
      ["VPC; subnets public / app / data / endpoint per AZ (2 dev, 3 staging / prod)",
       "Internet gateway, NAT gateways (1 dev, 1 per AZ staging / prod) - or central egress",
       "Route tables: public -> IGW; app -> NAT + WBD ranges via TGW; data and endpoint local only",
       "Transit Gateway attachment in the app subnets; WBD side: association / propagation of the VPC CIDR",
       "Gateway endpoints S3, DynamoDB; interface endpoints (13 core); glue endpoint (data platform; can wait for phase 10); bedrock-runtime (Release 2 only)",
       "Default security group with no rules; VPC flow logs (+ log group with key logs)",
       "The 13 security groups with the rules in section 7.2"],
      "Phases 2-3", "WBD Infra + WBD Network", "From a WBD machine, an IP in the app subnet is reachable through the TGW (e.g. a temporary test); from a private subnet, sts / ecr endpoints resolve to private IPs; NAT egress reaches *.okta.com.",
      "VPC ID, subnet IDs per tier, security group IDs, NAT Elastic IPs (for the Databricks IP access list).")

phase("Phase 5 - Registry, secrets, parameters, storage, alerts topic (layers 07, 08, 09, 19 SNS)",
      "Pipelines need ECR to push the first images; secrets / parameters and buckets are referenced by the tasks and Lambdas.",
      ["ECR repositories mmm/api, mmm/ui, mmm/optimizer (+ mmm/sagemaker-training for the data platform); enhanced scanning",
       "Secrets Manager containers (empty) - api/db, rds/migrate, rds/proxy, okta/alb-client (+ databricks/export-sp, optional splunk/hec, thirdparty/*). Owners fill the values.",
       "SSM parameters: okta/issuer, optimization/max_concurrent_runs (5 / 20 / 50), ecs/optimizer_task_definition (placeholder), images/sagemaker-training (placeholder), databricks/* (data platform), genai/* (Release 2)",
       "S3: logs bucket FIRST (others send access logs to it), then models, uploads (CORS = internal app URL), results, approved-worm (Object Lock at creation!), exports; data platform buckets landing, lakehouse, training-data (Object Lock at creation!), glue-assets",
       "SNS topic mmm-<env>-alerts + subscription"],
      "Phases 2-4", "WBD Infra; secret values by WBD Identity / Databricks / Splunk", "Pipelines can push a test image; buckets reject non-TLS and unencrypted uploads; Object Lock shows on the two WORM buckets.",
      "ECR repository URIs, secret ARNs, bucket names, SNS topic ARN.")

phase("Phase 6 - Database (layer 10)",
      "The API and the publisher need the database; DB users and their secrets must exist before the first deploy.",
      ["DB subnet group (data subnets), parameter group (rds.force_ssl = 1, pgaudit, slow-query logs)",
       "RDS PostgreSQL 16 instance (dev db.t4g.medium single-AZ 50 GB; staging db.r6g.large Multi-AZ 100 GB; prod db.r6g.xlarge Multi-AZ 200 GB), key rds, RDS-managed admin password, IAM auth, Performance Insights, Enhanced Monitoring role, log groups",
       "RDS Proxy + role (reads the DB user secrets), TLS required, IAM auth",
       "DB bootstrap: create users mmm_app and mmm_migrator and fill their secrets (one-off task by EY / backend with WBD; schema comes from the backend migrations)"],
      "Phases 4-5", "WBD Infra; DB users with EY / backend team", "Connection through the proxy with TLS from a task in the app subnet works for mmm_app.",
      "RDS instance ID, proxy endpoint.")

phase("Phase 7 - ECS, internal ALB, sign-in, DNS (layers 11, 12)",
      "This is the planner-facing application - the first visible milestone.",
      ["ECS cluster mmm-<env>-ecs (Fargate, Container Insights, ECS Exec logging), Service Connect namespace",
       "Roles: task execution role; task roles api, ui, migrate, platform-check (policies from the resource list / EY)",
       "Log groups /ecs/mmm-<env>/<service>",
       "Task definitions api (1 vCPU / 2 GB), ui (0.25 / 0.5), migrate, platform-check - first version with the first images from the repositories",
       "Certificate for the internal name (ACM or WBD private CA)",
       "Internal ALB in the app subnets with SG alb; target groups api-tg / ui-tg (port 8080); listener 443 with authenticate-oidc (Okta) first, rules /api/* and /api/health; listener 80 -> 443; access logs to the logs bucket",
       "ECS services api and ui (private subnets, circuit breaker rollback) + CPU auto scaling",
       "WBD DNS: CNAME internal name -> ALB DNS name; WBD Identity: Okta app redirect URI, client secret into okta/alb-client"],
      "Phases 4-6; images in ECR; Okta app", "WBD Infra, WBD DNS / PKI, WBD Identity", "CHECKPOINT - a planner on the WBD network opens the URL, is sent to Okta, signs in and sees the UI; /api/health returns 200; the URL is NOT reachable from outside the WBD network.",
      "Cluster name, service names, task-definition families, ALB DNS name, target group ARNs, listener ARN.")

phase("Phase 8 - Optimization engine (layer 13)",
      "Core business function of Release 1.",
      ["SQS queue mmm-<env>-optimization-requests + DLQ (key sqs, redrive after 10)",
       "Optimizer task definition (4 vCPU / 16 GB / 50 GiB; prod 8 / 32) + task role + log group; set SSM ecs/optimizer_task_definition",
       "Results/data publisher Lambda (+ live alias) in the VPC (SG lambda + data-clients) + role + log group",
       "Step Functions state machine optimization + role + log group",
       "Run dispatcher Lambda + role + SQS event source mapping"],
      "Phases 5-7", "WBD Infra; images / code from the repositories", "CHECKPOINT - one run from the UI (or a test message) goes QUEUED -> RUNNING -> results visible; run evidence under results/runs/<run_id>/.",
      "Queue URL, state machine ARN, Lambda names.")

phase("Phase 9 - Monitoring, backup, pipeline roles (layers 19, 20, 04)",
      "Go-live needs alarms, backups and working pipelines.",
      ["CloudWatch alarms (core 21), EventBridge alert rules, dashboards, logs data protection policy",
       "AWS Backup vault (key backup), daily plan, tag-based selection + role, backup-failed rule (DR vault only if approved)",
       "Complete the pipeline roles gha-ecr-push and gha-deploy with permissions on the resources above; trust the three repositories + environments",
       "Optional: Splunk Firehose + subscription filters; CloudTrail S3 data events on the buckets",
       "A pipeline runner on the WBD network / VPC for the post-deploy smoke test (the ALB is internal)"],
      "Phases 5-8", "WBD Infra / Security / repository owners", "A test alarm reaches on-call; first backup job succeeds; a pipeline deploys a new revision to dev and the smoke test passes.",
      "Role ARNs for the pipeline variables, SNS subscription confirmed.")
callout("Release 1 core:", "repeat phases 1-9 in staging and then prod (prod with deletion protection, Multi-AZ, COMPLIANCE Object Lock, "
        "365-day logs). Phase 10 is also part of Release 1 (slide 1), but can be built after the core is live.")

phase("Phase 10 - Data platform / model refresh (layers 14-17)",
      "Needed for the automatic model refresh and drift monitoring (slide 1); depends on WBD Databricks being ready.",
      ["Keys sagemaker and s3-<bu> (if not done in phase 2); buckets landing, lakehouse, training-data, glue-assets; glue endpoint; SGs glue, sagemaker, databricks-export",
       "IAM role databricks-uc (write-only; trust Databricks UC master role + external ID) -> Databricks admins create the storage credential + external location",
       "Export Trigger Lambda + role + log group; SSM databricks/host, databricks/export_job_ids; secret databricks/export-sp (filled by Databricks admins); NAT IPs on the Databricks IP access list",
       "Glue: catalog databases bronze / silver / gold, catalog encryption, security configuration, NETWORK connection, role, log group, Data Quality ruleset, 6 jobs (bronze, silver, gold, export-training, export-rds, export-monitor)",
       "SageMaker: role, model package group per BU, log groups; ECR mmm/sagemaker-training + SSM images/sagemaker-training",
       "Step Functions model-refresh and model-monitor + roles + log groups; EventBridge Scheduler groups + schedules (disabled until data is ready); rules on-demand, model package state; S3 EventBridge notifications on landing",
       "Data platform alarms (9) and the pipeline roles gha-model-eval / gha-model-approve"],
      "Phases 1-9; Databricks jobs and service principal", "WBD Infra, WBD Databricks admins, data team", "CHECKPOINT - one on-demand refresh per BU completes: raw files in landing, Bronze / Silver / Gold tables, training snapshot, model version PendingManualApproval, results in RDS.",
      "Glue job names, state machine ARNs, model package group names, Databricks UC role ARN + external ID.")

phase("Phase 11 - Release 2 GenAI on Amazon Bedrock (layer 18)",
      "Only after WBD Responsible AI approval (slide 2: 'Not part of R1').",
      ["Bedrock model access (Anthropic; OpenAI / Google only if approved), Bedrock token quota",
       "SCP allows Bedrock in the inference-profile regions (us-east-1, us-east-2, us-west-2) if a US cross-region profile is used",
       "Key genai; Bedrock guardrail + version; bedrock-runtime interface endpoint with endpoint policy",
       "API task role: invoke only approved models with the MMM guardrail (condition bedrock:GuardrailIdentifier) + ApplyGuardrail",
       "SSM genai_enabled (false -> true at go-live), genai/model_id, genai/guardrail, genai/token_quota/<bu>",
       "Optional: inference profiles per BU, model invocation logging; GenAI alarms (7)"],
      "Phases 1-9", "WBD Cloud Platform, WBD Infra, Responsible AI", "An explanation is generated for a test run; a call without the guardrail is denied; alarms in OK.",
      "Guardrail ID / version, model ID, endpoint ID.")

h("6.1 Summary: build order by layer", 2)
table(
    ["Phase", "Layers of the resource list", "Release / scope"],
    [
        ("0", "- (inputs, decisions)", "All"),
        ("1", "01 Account baseline, quotas", "Release 1"),
        ("2", "03 KMS (02 Terraform state only if used)", "Release 1 (genai key R2)"),
        ("3", "04 permission boundary, OIDC provider, budgets", "Release 1"),
        ("4", "05 Networking, 06 Security groups", "Release 1 (glue endpoint: data platform; bedrock-runtime: R2)"),
        ("5", "07 ECR, 08 Secrets / SSM, 09 S3, SNS topic", "Release 1"),
        ("6", "10 Database", "Release 1"),
        ("7", "11 ECS, 12 Internal entry + sign-in", "Release 1"),
        ("8", "13 Optimization engine", "Release 1"),
        ("9", "19 Monitoring, 20 Backup, 04 pipeline roles", "Release 1"),
        ("10", "14 Databricks export, 15 Glue, 16 SageMaker, 17 Orchestration", "Release 1 - data platform"),
        ("11", "18 GenAI on Bedrock", "Release 2"),
    ],
    widths=[1.5, 9, 6.5],
)

# ================================================================== 7
h("7. Network and security rules to apply")
h("7.1 Traffic paths", 2)
table(
    ["Path", "How it must work"],
    [
        ("Planner -> app", "WBD network -> Transit Gateway -> internal ALB (443 from WBD CIDRs only). Never 0.0.0.0/0, no internet-facing load balancer."),
        ("ALB -> Okta", "Outbound HTTPS from the ALB to *.okta.com through NAT (or routed egress). The ALB cannot use an HTTP proxy."),
        ("Export Lambda -> Databricks", "HTTPS through NAT (NAT IPs on the workspace IP access list) or Databricks PrivateLink."),
        ("Workloads -> AWS APIs", "Interface endpoints with private DNS + S3 / DynamoDB gateway endpoints; no internet."),
        ("API -> Bedrock (R2)", "bedrock-runtime interface endpoint only."),
        ("Browser -> S3 uploads", "Presigned HTTPS PUT via the WBD network path to S3 (or an S3 interface endpoint if WBD wants private upload)."),
        ("App -> database", "api / migrate / publisher -> RDS Proxy 5432 -> RDS 5432, TLS required. Optimizer and Glue have no DB access."),
    ],
    widths=[4, 13],
)
h("7.2 Security groups", 2)
table(
    ["SG", "Inbound", "Outbound"],
    [
        ("alb", "443, 80 from WBD CIDRs", "8080 to ui, api; 443 to Okta via NAT"),
        ("ui", "8080 from alb", "443 to endpoints / S3"),
        ("api", "8080 from alb", "443 to endpoints (incl. bedrock-runtime), S3, ALB signing keys"),
        ("data-clients", "-", "5432 to rds-proxy; 443 to endpoints / S3"),
        ("rds-proxy", "5432 from data-clients", "5432 to rds"),
        ("rds", "5432 from rds-proxy", "-"),
        ("optimizer", "-", "443 to endpoints / S3"),
        ("lambda", "-", "443 to endpoints / S3 (+ data-clients)"),
        ("tasks", "-", "443 to endpoints, S3, package indexes"),
        ("databricks-export", "-", "443 to Databricks and endpoints"),
        ("glue", "self (all)", "443 to endpoints / S3"),
        ("sagemaker", "self", "443 to endpoints / S3"),
        ("endpoints", "443 from VPC CIDR", "-"),
    ],
    widths=[3, 6, 8],
)
h("7.3 Security rules for every resource", 2)
bullets([
    "Every IAM role: least privilege for its one integration + the permission boundary; no IAM users or access keys.",
    "Every store encrypted with its customer-managed key; per-BU keys for BU data prefixes.",
    "Every bucket: versioning, SSE-KMS, TLS-only + deny unencrypted PUT, public access blocked, BucketOwnerEnforced, access logs to the logs bucket.",
    "Every log group: KMS key logs, retention 30 / 90 / 365 days (dev / staging / prod).",
    "Secrets only in Secrets Manager, filled by the owning team, never by email or in Git.",
    "Tags on every resource: Project, Environment, Owner, CostCenter, ManagedBy (+ backup = true where backed up).",
    "Names: mmm-<env>-<purpose>; buckets wbd-mmm-<env>-<purpose>-use1; secrets mmm/<env>/...; parameters /mmm/<env>/...",
])

# ================================================================== 8
h("8. Inputs needed from other WBD teams")
table(
    ["Team", "Provides", "Blocks phase"],
    [
        ("Cloud Platform", "Accounts, SCPs, Identity Center, quotas, Bedrock model access", "1, 11"),
        ("Network", "CIDRs, TGW + routing, WBD CIDRs for the ALB, egress", "4"),
        ("DNS / PKI", "Internal app name (CNAME), certificate", "7"),
        ("Identity (Okta)", "OIDC app per environment, groups, client secret", "7"),
        ("Repository owners / app teams", "Repositories, pipelines, first images, DB migrations", "5, 7, 8, 9"),
        ("Databricks admins", "Export jobs, service principal, UC storage credential + external location, IP access list", "10"),
        ("Data engineers / data science", "Glue scripts, DQ rules, training and optimizer images, model thresholds, approver", "8, 10"),
        ("Security / Audit", "Key admin, IAM standards, CloudTrail data events", "2, 3, 9"),
        ("Splunk (optional)", "HEC endpoint and token", "9"),
        ("Responsible AI / Legal", "Written approval for GenAI on Bedrock, model choice", "11"),
    ],
    widths=[4.5, 9.5, 3],
)

# ================================================================== 9
h("9. Questions the infra team is likely to ask")
for q, a in [
    ("Why NAT and an internet gateway if nothing is public?",
     "Outbound only: the ALB must reach Okta during sign-in and the export Lambda must reach the Databricks API. Inbound from the "
     "internet is impossible (internal ALB, no public IPs). With WBD central egress through the TGW they can be dropped."),
    ("Why no WAF / Route 53?",
     "v6 makes the app internal: only WBD ranges reach it through the Transit Gateway and Okta sign-in comes first. DNS is WBD internal DNS."),
    ("Why one ECS cluster and not three?",
     "On Fargate a cluster is a free logical grouping without capacity. Isolation comes from task roles, security groups and separate "
     "scaling; the optimizer is a short-lived task per run, not a service. Three clusters add work without benefit."),
    ("Can we create everything at once?",
     "Yes technically, but follow the phases: KMS keys and the boundary are referenced by everything, the TGW / certificate / Okta "
     "inputs block the entry, and task definitions need the first images in ECR."),
    ("What must be decided at creation time?",
     "VPC CIDR, S3 Object Lock on training-data and approved-worm, bucket names, RDS engine / subnet group, KMS key per store - "
     "changing these later means recreating the resource."),
    ("What do the repository pipelines change?",
     "Only images, new task-definition revisions, service updates, Lambda versions / alias, Glue scripts and SSM release pointers. "
     "Never networking, IAM, KMS or databases."),
    ("Does any data leave AWS for GenAI?",
     "No; Bedrock runs inside AWS and is reached through a VPC endpoint. A US cross-region inference profile may process requests in "
     "us-east-2 / us-west-2."),
    ("What does EY need from us to continue without AWS access?",
     "The handback values per phase (section 6), screen-share / read-only sessions for each checkpoint, and the logs or screenshots "
     "of any failed check. EY provides policy documents and fixes the pipelines / specifications."),
    ("Which resources are created at run time, not by us?",
     "Optimizer tasks per run, SageMaker training / processing jobs per refresh, lineage records - started by Step Functions."),
]:
    p = d.add_paragraph()
    p.add_run("Q: " + q).bold = True
    p.paragraph_format.space_after = Pt(0)
    d.add_paragraph("A: " + a).paragraph_format.space_after = Pt(6)

h("10. Resource count (aws_resource_list_6.xlsx summary)")
para("214 resource rows in 20 layers, 338 AWS objects in prod: 115 Required, 49 Required for the data platform, 10 Required for "
     "GenAI (Release 2), 20 Optional (only if WBD approves), 11 account baseline to verify, 4 quota requests, 5 created at run time. "
     "Largest layers: networking (48 objects in prod: subnets, routes, endpoints), monitoring (82: alarms, rules, dashboards, "
     "subscriptions), ECS (22), secrets / parameters (21).")

out = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / OUT
d.save(out)
print("written", out)

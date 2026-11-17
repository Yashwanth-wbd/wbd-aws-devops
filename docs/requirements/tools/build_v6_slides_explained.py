"""Build WBD_MMM_v6_Architecture_Slides_Explained.docx - box-by-box explanation of the two slides of
WBD_MMM_Architecture_6.pptx (what each component does, why the service is used, the flow) plus a review of
gaps in the drawn flow. For the WBD infrastructure team; no Terraform content.

    uv run --no-project --with python-docx python .\\build_v6_slides_explained.py <requirements folder>
"""
import sys
from pathlib import Path

import docx
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

OUT = "WBD_MMM_v6_Architecture_Slides_Explained.docx"
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


def bullets(items, style="List Bullet"):
    for it in items:
        p = d.add_paragraph(style=style)
        if isinstance(it, tuple):
            p.add_run(it[0]).bold = True
            p.add_run(it[1])
        else:
            p.add_run(it)
        p.paragraph_format.space_after = Pt(2)


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


def component(n, name, label, what, why):
    p = d.add_paragraph()
    r = p.add_run(f"{n}. {name}")
    r.bold = True
    r.font.color.rgb = NAVY
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.keep_with_next = True
    if label:
        q = d.add_paragraph()
        rr = q.add_run("On the slide: " + label)
        rr.italic = True
        rr.font.size = Pt(9)
        rr.font.color.rgb = GREY
        q.paragraph_format.space_after = Pt(0)
    para(what, bold="What it does: ")
    para(why, bold="Why this service: ")


# ================================================================== title
for txt, size, bold in [
    ("WBD Media-Mix Modeling (MMM) Platform", 22, True),
    ("The v6 architecture slides explained - component by component, with the flow and the reasons", 13, False),
]:
    p = d.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(txt)
    r.bold = bold
    r.font.size = Pt(size)
    if bold:
        r.font.color.rgb = NAVY
p = d.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("Source: WBD_MMM_Architecture_6.pptx (2 slides) - for the WBD infrastructure team - 17 Nov 2026")
r.italic = True
r.font.size = Pt(9)
r.font.color.rgb = GREY

para("This document walks through the two slides of WBD_MMM_Architecture_6.pptx exactly as they are drawn: every box, "
     "what it does, why that AWS service was chosen, and how the request or data flows from box to box. The last section "
     "reviews the drawn flow and lists the gaps - arrows or components that are missing or unclear on the slides - with how "
     "they are handled in the implementation. The detailed resource specification is aws_resource_list_6.xlsx.")

# ================================================================== 0
h("1. How to read the slides")
para("Both slides use the same layout:")
table(
    ["Area of the slide", "Meaning"],
    [
        ("Title + 'Hybrid design' line", "What the slide is about (slide 1: lakehouse + MLOps with auto refresh; slide 2: containerized optimization & decision application with GenAI, 50-150 planners)."),
        ("PLATFORM CONTROL PANE (top band)", "Cross-cutting capabilities that apply to everything: Data Lineage & Observability, Code Repository, Security - RBAC . SSO/MFA, Amazon Bedrock for GenAI capabilities, Privacy & GenAI Guardrails."),
        ("AWS Account frame", "Everything inside runs in a WBD-owned AWS account - one account per environment (dev, staging, prod)."),
        ("'AWS Services . Outside VPC' band", "Regional, serverless AWS services (S3, Step Functions, SQS, EventBridge, SageMaker Registry, ECR, ...) that are not placed in a subnet. They are still reached privately (VPC endpoints)."),
        ("VPC box (slide 2)", "The private network: internal ALB, ECS containers and RDS in private app / data subnets."),
        ("Labels 'AWS IAM' and 'KMS' on arrows / stores", "Every arrow is an IAM role with only the permissions for that integration; every data store is encrypted with a customer-managed KMS key."),
        ("Security + Network / Logging/Operations (bottom band)", "IAM / role assumption, IAM Identity Center, KMS, Secrets Manager, Security Groups, VPC routes; CloudWatch metrics, CloudTrail, Terraform, CI/CD."),
        ("Environment Level component", "Secrets Manager (credentials for APIs, RDS, integrations), VPC Routes (private paths), CloudWatch and CloudTrail 'to be enabled across all components'."),
        ("PRESCRIBED STACK", "WBD's mandated technologies: React + TypeScript, Python / FastAPI, scikit-learn / XGBoost / LangGraph, SciPy, RDS PostgreSQL + Databricks / S3, ECS, AWS recommended."),
    ],
    widths=[5.5, 11.5],
)
para("How the two slides connect: slide 1 produces approved models and response curves (SageMaker Registry + S3) and writes "
     "model results and reference data into RDS PostgreSQL; slide 2 uses those approved models / curves for every optimization "
     "run and shows the results from the same RDS database.")

# ================================================================== slide 1
h("2. Slide 1 - 'The Platform's technical architecture supports auto ML activities'")
para("Purpose: keep one media-mix model per business unit (streaming, theatrical, US networks) up to date automatically - a "
     "scheduled refresh (and a triggered refresh from the application) pulls data from Databricks, prepares it in a lakehouse, "
     "trains, evaluates and registers a new model, and publishes the results. 'Hybrid design: Platform Lakehouse and MLOps + "
     "supports auto refresh of the models ... Application supports triggered refresh as well.'")
h("2.1 Flow at a glance", 2)
diagram(
    " [Scheduled Refresh]\n"
    "      -> EventBridge -> Step Functions (Schedule / Manual, Wait / Retry)\n"
    "           -> Lambda 'Export Trigger' (Databricks API connector)\n"
    "                -> Databricks on AWS: Source Catalog, 'Responsible Export via jobs APIs'\n"
    "                -> Raw data in S3 (ingested inventory, 3+ years of history)\n"
    "           -> AWS Glue + Data Catalog (Lineage):  Bronze -> Silver -> Gold\n"
    "                (Delta Lake storage backed by S3: Bronze / Silver / Gold layers)\n"
    "           -> Glue Export -> Training data in S3 (immutable Parquet + metadata)\n"
    "           -> Glue Export -> Lambda 'Results/data publisher' -> RDS PostgreSQL\n"
    "           -> SageMaker (in the VPC via SageMaker VPC ENI):\n"
    "                Model Training -> Evaluation (Baseline -> Channel Lift -> Title Adjustment)\n"
    "                -> Model Registration -> SageMaker Registry + S3 (approved models, response curves,\n"
    "                   lineage, model drift monitoring)\n"
    "           -> Lambda 'Results/data publisher' -> RDS: model predictions, lift & evaluation results"
)
h("2.2 Components, in the order of the flow", 2)
component(1, "Trigger - Amazon EventBridge + AWS Step Functions",
          "'EventBridge -> Step Functions / Schedule / Manual . Wait / Retry', 'Scheduled Refresh'",
          "EventBridge Scheduler starts a refresh per business unit on a schedule (proposed weekly, Monday 06:00 New York). An "
          "application or manual request (an EventBridge event) starts a triggered refresh for one BU. EventBridge starts the "
          "Step Functions state machine 'model-refresh', which runs every following step in order, waits for long jobs and "
          "retries transient failures.",
          "EventBridge gives cron schedules in a timezone and event-driven triggers without servers. Step Functions is AWS's "
          "serverless workflow engine: it calls Lambda, Glue and SageMaker natively, waits for them to finish (.sync), has "
          "built-in retry / timeout / error branches and keeps an auditable history of every run. Chosen instead of Airflow "
          "(MWAA), which would be an always-on environment to operate.")
component(2, "Export Trigger - AWS Lambda (Databricks API connector)",
          "'Lambda Functions / Export Trigger', 'Databricks API connector', 'AWS IAM'",
          "A small function called by Step Functions. It reads the Databricks service-principal credentials from Secrets Manager, "
          "obtains an OAuth token, starts the export job of the business unit through the Databricks Jobs API, and is called again "
          "to poll the job status until it has finished.",
          "The work is a few short API calls - ideal for Lambda (no server, pay per call). Keeping it in AWS means AWS decides "
          "when and what is exported, while Databricks remains only the source.")
component(3, "Databricks on AWS - Source Catalog",
          "'Databricks on AWS', 'Databricks Source Catalog / Responsible Export via jobs APIs'",
          "WBD's existing Databricks workspace holds the source data (media spend, outcomes, inventory). An export job owned by "
          "the WBD Databricks admins selects the approved data for one BU and writes it to S3 ('responsible export').",
          "Databricks is WBD's data platform and the system of record for this data; the MMM platform does not copy the whole "
          "catalog, only what each refresh needs, through an auditable job.")
component(4, "Raw data in Amazon S3 (landing)",
          "'Raw data coming from Databricks coming to S3 / Ingested inventory 3+ years historical data', 'KMS'",
          "The export job writes Parquet files (3+ years of history) into the landing bucket under raw/databricks/<bu>/<date>/ "
          "through a write-only IAM role. Each BU's files are encrypted with that BU's KMS key.",
          "S3 is the durable, cheap, scalable landing zone that Glue and SageMaker read natively. A write-only role means "
          "Databricks can drop files but cannot read anything else in AWS; per-BU keys keep business units separated.")
component(5, "AWS Glue + Data Catalog (Lineage) - Bronze layer",
          "'INGEST', 'Bronze Layer Ingested Raw data'",
          "A Glue Spark job reads the raw Parquet and stores it as Bronze Delta tables - the raw data, unchanged, but queryable and "
          "versioned - and registers the tables in the Glue Data Catalog.",
          "Glue is serverless Spark: it scales to the data size and costs nothing between refreshes. The Data Catalog is the "
          "central table registry; table properties record the lineage of each refresh.")
component(6, "Silver layer",
          "'Silver Layer / Cleansed and validated data'",
          "A second Glue job cleanses and conforms the data and validates it with Glue Data Quality rules. If a rule fails the "
          "refresh stops and an alert is sent - bad data never reaches model training.",
          "Glue Data Quality runs the rules inside the same job (no extra tool) and produces a pass / fail result Step Functions can act on.")
component(7, "Gold layer",
          "'Gold Layer / Per-BU modeling tables / Adstock & saturation'",
          "A third Glue job builds the modeling tables per business unit, including adstock (carry-over of advertising over time) "
          "and saturation (diminishing returns) features.",
          "Separating Gold from Silver keeps business logic (modeling features) apart from data cleansing, so each can change "
          "and be tested on its own.")
component(8, "Delta Lake storage backed by S3",
          "'Delta Lake Storage | Backed by S3 / Bronze / Silver / Gold layer', 'KMS'",
          "All three layers are stored as Delta Lake tables in the S3 lakehouse bucket.",
          "Delta Lake (supported natively by Glue 5.0) adds ACID writes, table versions and time travel on top of S3 - every "
          "refresh can be traced to an exact table version, which supports lineage and reproducibility.")
component(9, "Glue Export -> Training data in S3",
          "'Glue Export', 'Training data | Stored in S3 / Immutable Parquet + metadata', 'KMS'",
          "A Glue export job writes a snapshot of the Gold tables as Parquet plus a metadata file to the training-data bucket, "
          "one folder per refresh. The bucket uses S3 Object Lock so the snapshot cannot be changed.",
          "SageMaker reads plain Parquet efficiently. An immutable snapshot means every model version can be reproduced and "
          "audited from exactly the data it was trained on.")
component(10, "Glue Export -> Lambda 'Results/data publisher' -> RDS PostgreSQL (reference data)",
          "'Glue Export', 'Lambda Functions / Results/data publisher', 'RDS PostgreSQL / Plans . Runs . Allocations'",
          "A second Glue export writes the Gold reference tables the application needs (e.g. titles, inventory history) as "
          "Parquet; the results/data publisher Lambda loads them into RDS PostgreSQL through RDS Proxy.",
          "Only one small component (the publisher) has write access to the database - Glue jobs never connect to RDS. This "
          "keeps database credentials and network access minimal and the database schema owned by the backend.")
component(11, "Amazon SageMaker - Model Training (in the VPC)",
          "'AWS Native . SageMaker Modeling', 'Model Training / Trained and Tuned multi-stage models from the Parquet files', 'SageMaker VPC ENI'",
          "A SageMaker training job runs the data scientists' training container on the training snapshot and writes the model "
          "artifact and the drift baseline to S3. It runs in the private subnets (SageMaker VPC ENI), so no data leaves the network.",
          "SageMaker provides managed, on-demand ML compute (no idle instances), container-based training with scikit-learn / "
          "XGBoost, VPC isolation and KMS encryption, and integrates with the registry and lineage.")
component(12, "Evaluation - Baseline -> Channel Lift -> Title Adjustment",
          "'Evaluation', 'Baseline', 'Channel Lift', 'Title Adjustment'",
          "A SageMaker processing job evaluates the multi-stage model: baseline (what happens without media), channel lift (the "
          "contribution of each channel) and title adjustment (per-title effects). It writes the evaluation report, predictions, "
          "lift and the response curves.",
          "Processing jobs run the same container on demand, separate from training, so evaluation results are a stored, "
          "reviewable artifact used by the approval step.")
component(13, "Model Registration - SageMaker Registry + S3",
          "'Model Registration / Approved model versioned and registered', 'SageMaker Registry + S3 / Approved models and response curves + lineage + model drift monitoring', 'KMS'",
          "The new version is registered in the SageMaker Model Registry (one model group per BU) as 'pending approval'. A named WBD "
          "approver approves it (after automatic threshold checks); the approved response curves are then published in S3 for the "
          "optimizer. Lineage links the Databricks export, Glue table versions, training snapshot, training job and model version. "
          "A daily drift check compares new data with the approved model's baseline and alarms when the model is out of date.",
          "The registry gives versioning, approval status and an audit trail out of the box (governance: no model is used without "
          "human approval). SageMaker ML Lineage Tracking records where every model came from.")
component(14, "Lambda 'Results/data publisher' -> RDS PostgreSQL (model results)",
          "'Model Predictions, Lift & Evaluation results written in RDS for corresponding dataset'",
          "The publisher writes the model's predictions, lift and evaluation results into RDS, tagged with the model version, so the "
          "application shows them next to the dataset they belong to.",
          "Same single writer as above; RDS is the application's system of record, so planners see model results in the app "
          "without querying S3 or SageMaker.")

# ================================================================== slide 2
h("3. Slide 2 - 'The Platform's technical architecture supports optimization and explainable planning'")
para("Purpose: the planner-facing application. 'Hybrid design: MLOps + containerized optimization & decision application with "
     "GenAI capabilities ... enabling simultaneous usage of 50-150 planners during planning seasons.' The application is internal "
     "(v6): it has no public entry.")
h("3.1 Flow at a glance", 2)
diagram(
    " Planner: 'Upload Inventory + choose objective + run & Compare  OR  Upload Future titles'\n"
    "   -> SSO / Authentication - Okta (enterprise IdP, authentication + RBAC; IAM Identity Center)\n"
    "   -> VPC . Internal ALB + Private App/Data Subnets:  ALB / HTTPS\n"
    "        -> ECS UI (Fargate web container with QA Dashboard)  <->  ECS API (FastAPI, LangGraph tools)\n"
    "           [One ECS cluster on AWS Fargate . Containerized App]\n"
    "        API -> S3 'Store user input files' (User file upload to S3)\n"
    "        API -> SQS -> Lambda 'message dispatcher' -> Step Functions (Async Execution)\n"
    "             -> ECS Inference and Optimization Fargate container:\n"
    "                  Model Summarizer -> Optimizer -> Simulation\n"
    "                  (uses SageMaker Registry approved models + approved MMM response curves in S3)\n"
    "             -> S3 Outputs (Full Run Evidence) -> Lambda 'Results publisher' -> RDS (Plans . Runs . Allocations)\n"
    "   Not part of R1:  API (LangGraph explanation tool) -> Amazon Runtime VPC Endpoint\n"
    "             -> Amazon Bedrock (Anthropic Models default; Open AI / Google Models optional)\n"
    "                with Amazon Bedrock Guardrails\n"
    "   Build and Deploy - ECR: UI + API container images, versioned releases -> ECS"
)
h("3.2 Components, in the order of the flow", 2)
component(1, "Planner actions",
          "'Upload Inventory + choose objective + run & Compare / OR / Upload Future titles'",
          "Two kinds of run: optimize (upload an inventory file, choose an objective, run and compare scenarios) and forecast "
          "(upload future titles). Planners also compare, approve and export scenarios.",
          "-")
component(2, "SSO / Authentication - Okta",
          "'SSO / Authentication - Okta / Enterprise Identity Provider used for authentication and RBAC / IAM Identity Center'",
          "The planner authenticates with WBD Okta first (single sign-on + MFA). Okta returns the user's groups (business unit, role), "
          "which the application uses for role-based access control. The ALB performs this sign-in (OIDC) before forwarding any "
          "request. IAM Identity Center, also federated with Okta, is how engineers (not planners) sign in to the AWS accounts.",
          "Okta is WBD's enterprise identity provider - one identity, existing MFA policies, groups managed centrally. The ALB has "
          "native OIDC support, so no sign-in code is needed in the application and unauthenticated traffic never reaches it.")
component(3, "VPC . Internal ALB + Private App/Data Subnets - ALB / HTTPS",
          "'VPC . Internal ALB + Private App/Data Subnets', 'ALB / HTTPS'",
          "An internal Application Load Balancer in the private app subnets is the single entry point. It terminates HTTPS, runs "
          "the Okta sign-in, then routes /api/* to the API containers and everything else to the UI containers. It is reachable only "
          "from the WBD network (offices, VPN, VDI) through the WBD Transit Gateway; the app name is a record in WBD internal DNS.",
          "An internal ALB gives private-only access (v6: no public entry, no WAF, no Route 53), path-based routing to containers, "
          "health checks, TLS and Okta OIDC in one managed service.")
component(4, "One ECS cluster on AWS Fargate - ECS UI",
          "'One ECS cluster on AWS Fargate . Containerized App', 'ECS UI / Fargate Web Container with QA Dashboard'",
          "The web application (React + TypeScript) with the QA dashboard runs as a Fargate service - 1-2 tasks in dev, up to 6 in "
          "prod, scaled on CPU.",
          "Fargate runs containers without servers to manage or patch, scales task by task for planning-season peaks, and is the "
          "prescribed compute ('ECS'). One cluster for all containers: on Fargate a cluster is a free logical grouping; isolation "
          "comes from each container's own IAM role, security group and scaling.")
component(5, "ECS API - Fargate API container with LangGraph tools",
          "'ECS API / Fargate API Container / With LangGraph tools (invoke explanation tool by default for every run)'",
          "The Python FastAPI backend: plans, scenarios, synchronous what-if simulations, presigned upload URLs, queuing of runs, "
          "results from RDS. LangGraph orchestrates tools, including the explanation tool (Release 2) that is invoked for every run.",
          "Same Fargate benefits; the API scales independently of the UI (up to 10 tasks in prod). LangGraph is the prescribed "
          "framework for tool-using GenAI flows.")
component(6, "S3 - Store user input files",
          "'S3 / Store user input files', 'User file upload to S3', 'KMS'",
          "Inventory and future-title files are stored per BU and run. The browser uploads directly to S3 with a short-lived "
          "presigned URL issued by the API; the inference container reads the file.",
          "S3 handles large files without passing them through the API containers; presigned URLs give time-limited, per-object "
          "permission; KMS encryption and lifecycle expiry (90 days) protect the data.")
component(7, "Amazon SQS",
          "'SQS'",
          "The API puts each run request on a queue and returns immediately; the run shows as queued.",
          "50-150 planners can submit many runs at once in planning season. The queue absorbs bursts, never loses a request "
          "(dead-letter queue after repeated failures) and decouples the web tier from the heavy computation.")
component(8, "Lambda functions - message dispatcher",
          "'Lambda functions - message dispatcher'",
          "Reads the queue and starts a Step Functions execution only while fewer than the allowed number of runs are running "
          "(5 dev / 20 staging / 50 prod, changeable without redeploy).",
          "Controls concurrency so runs fit within the Fargate capacity and the database, and allows pausing new runs. A small, "
          "event-driven function - Lambda is the simplest fit.")
component(9, "Step Functions - Async Execution",
          "'Step Functions / Async Execution'",
          "One execution per run: starts the inference & optimization container, waits for it, handles retries and timeouts, then "
          "calls the results publisher.",
          "Same reasons as on slide 1: managed orchestration with waiting, retries, timeouts and a visible history per run - the "
          "run ID is the execution name, which makes support easy.")
component(10, "ECS Inference and Optimization Fargate container - Model Summarizer, Optimizer, Simulation",
          "'ECS Inference and Optimization Fargate container', 'Model Summarizer', 'Optimizer', 'Simulation'",
          "One Fargate task per run, in the same ECS cluster. Inside the one container the three functions run in sequence: Model "
          "Summarizer (summarizes the approved model for the BU), Optimizer (SciPy-based budget allocation for the objective), "
          "Simulation (simulates the outcome of the plan). 4 vCPU / 16 GB (prod 8 vCPU / 32 GB), up to 60 minutes.",
          "Each run gets its own isolated compute that exists only while the run lasts (no idle cost) and cannot affect the web "
          "tier. v6 answer to 'separate clusters or three services?': neither - one cluster, one task per run; the three steps share "
          "data in memory, so splitting them would only add hand-offs.")
component(11, "SageMaker Registry - stored approved models; Approved MMM response curves in S3",
          "'SageMaker Registry / Stored approved models', 'Approved MMM response curves in S3', 'KMS'",
          "The inference container uses only the model version approved on slide 1 and its published response curves.",
          "This is the link to slide 1: governance guarantees planners only optimize on approved, versioned models.")
component(12, "S3 Outputs - Full Run Evidence",
          "'S3 Outputs / Full Run Evidence', 'AWS IAM'",
          "The container writes all inputs, outputs and solver logs of the run to the results bucket.",
          "Complete, cheap, durable evidence for audit and support; the database keeps only what the app displays.")
component(13, "Lambda functions - Results publisher -> RDS PostgreSQL",
          "'Lambda Functions / Results publisher', 'RDS PostgreSQL / Plans . Runs . Allocations'",
          "Called by Step Functions after the container finishes: loads the run results from S3 into RDS (plans, runs, allocations). "
          "The UI then shows the run as complete.",
          "Single database writer for batch results (the container has no database access). RDS PostgreSQL is the prescribed "
          "relational store; it supports row-level security per business unit and Multi-AZ high availability.")
component(14, "Amazon Bedrock - Anthropic (default), OpenAI / Google (optional) - Not part of R1",
          "'Amazon Bedrock', 'Anthropic Models (Default)', 'Open AI Models (Optional)', 'Google Models (Optional)', 'Not part of R1'",
          "In Release 2 the API's explanation tool sends the run results to a Bedrock model (Converse API) and receives a "
          "plain-language explanation of the plan. Anthropic Claude is the default; OpenAI and Google models served by Bedrock are "
          "kept as optional alternatives for experimentation.",
          "Bedrock runs the models inside AWS with IAM access - no external API keys, no data sent to external providers, one API for "
          "all three model families, and pay per token. It replaces the earlier API Gateway LLM gateway (removed in v6).")
component(15, "Amazon Runtime VPC Endpoint",
          "'Amazon Runtime VPC Endpoint'",
          "The bedrock-runtime interface endpoint inside the VPC; the API reaches Bedrock privately through it.",
          "Keeps GenAI traffic off the internet; its endpoint policy restricts use to this account and the approved models.")
component(16, "Amazon Bedrock Guardrails",
          "'Amazon Bedrock Guardrails', control pane 'Privacy & GenAI Guardrails'",
          "Applied inside every model call to the prompt and the answer: blocks prompt attacks, harmful content and denied topics, "
          "masks / blocks personal data, checks that the answer is grounded in the run data and relevant.",
          "Native, configurable protection with versioning; IAM can require the guardrail on every call, so no request can skip it.")
component(17, "Build and Deploy - Amazon ECR",
          "'Build and Deploy - ECR / UI + API container Images . Versioned releases'",
          "Private container registry per account. The CI/CD pipelines of the WBD repositories push versioned images; ECS pulls "
          "them for each release.",
          "Native to ECS, private (pulled through VPC endpoints), image scanning, immutable version tags for traceable releases.")

# ================================================================== control pane
h("4. The control pane and the bottom bands (both slides)")
table(
    ["Element", "What it means in the build", "Why"],
    [
        ("Data Lineage & Observability", "Glue Data Catalog lineage properties + SageMaker ML Lineage; CloudWatch logs, metrics, alarms and dashboards on every component", "Trace every model and number back to its data; detect problems before planners do"),
        ("Code Repository", "WBD's frontend, backend and data repositories; their pipelines build images and deploy code (keyless OIDC login)", "Versioned, reviewed changes; no manual deployments"),
        ("Security - RBAC . SSO/MFA", "Okta sign-in + groups; app RBAC; PostgreSQL row-level security per BU", "Planners see only their business unit's data"),
        ("Amazon Bedrock for GenAI capabilities", "Bedrock models through the VPC endpoint (Release 2)", "GenAI inside AWS"),
        ("Privacy & GenAI Guardrails", "Bedrock Guardrails + IAM enforcement + optional invocation logging", "Responsible AI"),
        ("AWS IAM / role assumption", "One least-privilege role per arrow, all under a permission boundary", "A compromised component can only do its own job"),
        ("IAM Identity Center", "Engineer access to the AWS accounts via Okta; no IAM users", "No long-lived credentials"),
        ("KMS", "Customer-managed keys per purpose and per business unit", "Encryption at rest with control over who can decrypt"),
        ("Secrets Manager", "DB users, Okta client secret, Databricks service principal", "No secrets in code, images or pipelines"),
        ("Security Groups / VPC routes", "One SG per component; routes to the WBD network via the Transit Gateway; endpoints", "Private, least-privilege network paths"),
        ("CloudWatch / CloudTrail", "Logs, metrics, alarms, dashboards; audit of every API call (+ S3 data events)", "'To be enabled across all components'"),
        ("Terraform / CI/CD", "Infrastructure as code (WBD Infra's tooling; EY's Terraform is the reference); pipelines for app code", "Repeatable environments dev -> staging -> prod"),
    ],
    widths=[4, 7.5, 5.5],
)

# ================================================================== why summary
h("5. Why these services - summary")
table(
    ["Need", "Service chosen", "Main reason", "Not chosen / why"],
    [
        ("Run containers (UI, API, optimizer)", "ECS on Fargate", "Prescribed; serverless; per-task scaling and isolation", "EKS (more to operate), EC2 (patching)"),
        ("Private entry + sign-in", "Internal ALB + Okta OIDC", "Native OIDC, internal-only, path routing", "Public ALB / WAF / Route 53 / API Gateway - removed in v6"),
        ("Burst handling of runs", "SQS + dispatcher Lambda", "Never lose a request; cap concurrency", "Direct start from the API (no back-pressure)"),
        ("Orchestration", "Step Functions", "Waits, retries, history, native Lambda / Glue / SageMaker / ECS calls", "MWAA (always-on), custom code"),
        ("Data source", "Databricks export via Jobs API", "Databricks stays system of record", "Direct JDBC reads from AWS"),
        ("Lakehouse", "S3 + Delta Lake + Glue + Data Catalog", "Serverless Spark, ACID tables, lineage", "Redshift / EMR (more to run)"),
        ("Data quality", "Glue Data Quality", "Built into the Silver job", "Separate tool"),
        ("Model training / registry", "SageMaker", "On-demand ML compute in the VPC; registry + approval + lineage", "Self-managed MLflow"),
        ("Application database", "RDS PostgreSQL + RDS Proxy", "Prescribed; RLS; pooling for many tasks", "-"),
        ("Files and evidence", "S3 (+ Object Lock)", "Durable, cheap, immutable where required", "-"),
        ("GenAI", "Amazon Bedrock + Guardrails via VPC endpoint", "In-account models, IAM, no API keys", "External APIs through API Gateway (removed in v6)"),
        ("Images", "ECR", "Private, scanned, versioned", "-"),
        ("Observability / audit", "CloudWatch, CloudTrail", "Native on every service", "-"),
    ],
    widths=[3.3, 3.7, 5, 5],
    font=8.5,
)

# ================================================================== gaps
h("6. Review: is the drawn flow correct? Gaps and recommendations")
para("Verdict: the flow on both slides is correct and consistent with the v6 requirements - Okta before the ALB, internal ALB, "
     "one ECS cluster with the three inference functions in one task, SQS -> dispatcher -> Step Functions, S3 evidence -> "
     "publisher -> RDS, Bedrock with Anthropic default behind a VPC endpoint with guardrails, and on slide 1 the full "
     "export -> medallion -> train -> evaluate -> register -> publish chain. There is no logical error. The gaps below are "
     "arrows that are missing or ambiguous, components that must exist but are not drawn, and a few points that need a "
     "decision. Each is already covered in aws_resource_list_6.xlsx / the implementation; they should be clarified with the "
     "architect so the infra team does not misread the slides.", bold=None)

h("6.1 Slide 2 - arrows missing or ambiguous", 2)
table(
    ["#", "Gap on the slide", "Why it matters", "How it is handled / recommendation"],
    [
        ("G1", "No arrow from Step Functions to the ECS Inference & Optimization container (only API -> SQS -> dispatcher -> Step Functions and Step Functions -> publisher are drawn)",
         "The most important step of the run (who starts the container) is not visible", "Step Functions starts one Fargate task per run (ecs:runTask.sync) in the same cluster. Add the arrow."),
        ("G2", "No arrow API -> RDS; RDS Proxy not drawn", "The API reads / writes plans and runs and needs database access and connection pooling", "API -> RDS Proxy -> RDS (IAM auth, TLS). RDS Proxy is in the resource list (layer 10)."),
        ("G3", "Network path from the WBD network to the internal ALB not drawn (Transit Gateway / VPN, WBD internal DNS)",
         "With no public entry, this path is the only way in - it is a hard prerequisite", "Transit Gateway attachment + routes + WBD DNS CNAME (layer 05, outside_aws). Draw 'WBD network -> TGW -> Internal ALB'."),
        ("G4", "ALB -> Okta egress not drawn (NAT gateway)", "An internal ALB still calls Okta's token / user-info endpoints; without egress sign-in fails", "NAT gateways (or WBD central egress) in the public subnets, outbound only (layer 05)."),
        ("G5", "'User file upload to S3' drawn from the API; the inference container -> uploads read is not drawn",
         "Shows the data flow differently from the design; network team must know the browser talks to S3", "Browser uploads directly with a presigned URL from the API; the container reads the file. Decide whether browser -> S3 may use the WBD egress path or must use an S3 interface endpoint (private upload)."),
        ("G6", "Lambdas, SQS and Step Functions drawn in 'AWS Services . Outside VPC'", "The publisher must reach RDS, which is private", "Lambdas run inside the VPC (private subnets); SQS / Step Functions are reached via VPC endpoints (decision Q13)."),
        ("G7", "ECR box shows only 'UI + API container images'", "The optimizer and the SageMaker training images also need repositories", "ECR repositories mmm/api, mmm/ui, mmm/optimizer, mmm/sagemaker-training (layer 07)."),
        ("G8", "API is labelled 'invoke explanation tool by default for every run' while Bedrock is 'Not part of R1'", "Contradiction for Release 1 behaviour", "In R1 the switch genai_enabled = false and the run completes without explanation (decision Q20 / input 88)."),
    ],
    widths=[1, 5.2, 4.6, 6.2],
    font=8.5,
)
h("6.2 Slide 1 - arrows missing or ambiguous", 2)
table(
    ["#", "Gap on the slide", "Why it matters", "How it is handled / recommendation"],
    [
        ("G9", "Arrow from the Export Trigger Lambda straight into the Bronze layer", "Suggests the Lambda moves the data", "The Lambda only starts / polls the Databricks job; Databricks writes to S3 landing and the Glue Bronze job reads from there."),
        ("G10", "How Databricks writes into the AWS account is not drawn", "Cross-account write permission is a setup step for two teams", "Write-only IAM role used by a Unity Catalog storage credential + external location (layer 14)."),
        ("G11", "Model drift monitoring only appears as text in 'SageMaker Registry + S3 ... model drift monitoring'", "A separate daily workflow and alarm must be built", "Daily schedule per BU -> Step Functions model-monitor -> SageMaker drift job -> ModelDrift alarm (layer 17)."),
        ("G12", "Human approval of a model version not drawn", "Governance step and approver role must exist", "Registry status PendingManualApproval; named WBD approver via the model-governance pipeline; approved curves published to S3."),
        ("G13", "Publisher arrow comes from 'Evaluation', i.e. before registration / approval", "Unclear whether RDS should show results of unapproved models", "Implementation writes results after registration, tagged with the model version (decision input 84: every registered version or only approved). Confirm."),
        ("G14", "Glue jobs not shown in the VPC; only 'SageMaker VPC ENI' is drawn", "Glue needs subnets, a security group and the glue endpoint", "Glue NETWORK connection in the private app subnets (layer 15)."),
        ("G15", "Lineage store not explicit ('AWS Glue + Data Catalog (Lineage)')", "What must be traceable must be agreed", "Glue catalog table properties + SageMaker ML Lineage Tracking; optional DataZone UI (decisions Q14 / Q15)."),
        ("G16", "Triggered refresh from the application not drawn", "The API needs permission to send the refresh event", "EventBridge event mmm.refresh from the API / approver (rule model-refresh-on-demand)."),
    ],
    widths=[1, 5.2, 4.6, 6.2],
    font=8.5,
)
h("6.3 Components required but not drawn on either slide", 2)
bullets([
    "Transit Gateway attachment, NAT gateways, route tables and the interface VPC endpoints (ECR, STS, KMS, Logs, SQS, Step Functions, Secrets Manager, SSM, SageMaker, Glue) - only the Bedrock runtime endpoint is drawn.",
    "SQS dead-letter queue, RDS Proxy, ACM certificate for the internal app name.",
    "SNS alert topic, CloudWatch alarms and dashboards, EventBridge alert rules (covered by 'CloudWatch ... across all components').",
    "AWS Backup (RDS and buckets), budgets / cost anomaly alerts.",
    "S3 buckets for approved scenarios (Object Lock) and Excel exports, ALB / S3 access-log bucket.",
    "Three AWS accounts (dev, staging, prod) - the slides show one 'AWS Account'.",
    "A CI/CD runner inside the WBD network for post-deploy smoke tests (the ALB is internal; hosted runners cannot reach it).",
])
h("6.4 Recommendation", 2)
para("Ask the architect to add the arrows G1 (Step Functions -> inference container), G2 (API -> RDS Proxy -> RDS), G3 / G4 "
     "(WBD network -> Transit Gateway -> internal ALB, ALB -> NAT -> Okta) and G9 (Databricks -> S3 landing -> Glue Bronze) to "
     "the deck, and to confirm G5, G8 and G13 as decisions. None of the gaps changes the architecture or the resource list - "
     "they are already part of aws_resource_list_6.xlsx and the reference implementation.")

out = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / OUT
d.save(out)
print("written", out)

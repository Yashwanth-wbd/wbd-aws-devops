"""Build WBD_MMM_v6_Architecture_Explained.docx - plain-language walkthrough of the v6 architecture,
flows and AWS service list for the WBD infrastructure team (no Terraform content).

Source: WBD_MMM_Architecture_6.pptx, aws_resource_list_6.xlsx, devops_6_client_question.xlsx.

    uv run --no-project --with python-docx python .\\build_v6_explained.py <requirements folder>
"""
import sys
from pathlib import Path

import docx
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

OUT = "WBD_MMM_v6_Architecture_Explained.docx"
NAVY = RGBColor(0x1F, 0x3A, 0x5F)
GREY = RGBColor(0x55, 0x55, 0x55)

d = docx.Document()
for s in d.sections:
    s.left_margin = s.right_margin = Cm(2)
    s.top_margin = s.bottom_margin = Cm(1.8)
st = d.styles["Normal"]
st.font.name = "Calibri"
st.font.size = Pt(10.5)


def shade(cell, hex_fill):
    tc = cell._tc.get_or_add_tcPr()
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear")
    sh.set(qn("w:color"), "auto")
    sh.set(qn("w:fill"), hex_fill)
    tc.append(sh)


def h(text, level=1):
    p = d.add_heading(text, level=level)
    for r in p.runs:
        r.font.color.rgb = NAVY
    return p


def para(text, bold_prefix=None, italic=False, size=None):
    p = d.add_paragraph()
    if bold_prefix:
        r = p.add_run(bold_prefix)
        r.bold = True
    r = p.add_run(text)
    r.italic = italic
    if size:
        r.font.size = Pt(size)
    p.paragraph_format.space_after = Pt(4)
    return p


def bullets(items, style="List Bullet"):
    for it in items:
        p = d.add_paragraph(style=style)
        if isinstance(it, tuple):
            r = p.add_run(it[0])
            r.bold = True
            p.add_run(it[1])
        else:
            p.add_run(it)
        p.paragraph_format.space_after = Pt(2)


def steps(items):
    bullets(items, style="List Number")


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
            r = cells[i].paragraphs[0].add_run(str(v))
            r.font.size = Pt(font)
    if widths:
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
    d.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def diagram(text):
    p = d.add_paragraph()
    r = p.add_run(text)
    r.font.name = "Consolas"
    r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
    r.font.size = Pt(8)
    p.paragraph_format.space_after = Pt(6)
    pPr = p._p.get_or_add_pPr()
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear")
    sh.set(qn("w:fill"), "F2F4F7")
    pPr.append(sh)


def note(text):
    p = para(text, bold_prefix="Note: ")
    for r in p.runs:
        r.font.color.rgb = GREY


# ------------------------------------------------------------------ title
t = d.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = t.add_run("WBD Media-Mix Modeling (MMM) Platform")
r.bold = True
r.font.size = Pt(22)
r.font.color.rgb = NAVY
t = d.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = t.add_run("v6 architecture, end-to-end flows and AWS service list - explained for the WBD infrastructure team")
r.font.size = Pt(13)
t = d.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = t.add_run("Based on WBD_MMM_Architecture_6.pptx, aws_resource_list_6.xlsx and devops_6_client_question.xlsx - 17 Nov 2026")
r.italic = True
r.font.size = Pt(9)
r.font.color.rgb = GREY

table(
    ["Companion file", "What it gives you"],
    [
        ("WBD_MMM_Architecture_6.pptx", "The two architecture slides (slide 1 auto ML / model refresh, slide 2 optimization and explainable planning)."),
        ("aws_resource_list_6.xlsx", "Every AWS resource to create (214 rows, 20 layers) with names and sizes per environment; sheets architecture_flow, alarms_and_events, outside_aws, summary. Row numbers quoted below as 'row N' refer to its all_resources sheet."),
        ("devops_6_client_question.xlsx", "109 inputs WBD provides (client_inputs) and 36 design decisions with a proposed default (decisions_to_confirm, Q1-Q36)."),
        ("This document", "How the pieces fit together: what each flow does, step by step, which AWS services take part, and why. No Terraform or code."),
    ],
    widths=[5, 12],
)

# ------------------------------------------------------------------ 1
h("1. The project in one page")
para(
    "WBD's media planners decide how to spend marketing budgets across channels (TV, digital, social, ...) for each "
    "business unit (streaming, theatrical, US networks). The MMM platform replaces a third-party tool. It learns from "
    "3+ years of history how each channel drives results (a media-mix model with adstock and saturation curves), and "
    "lets planners run optimizations and forecasts on top of those models: upload an inventory or a list of future "
    "titles, choose an objective, run, compare scenarios, approve and export."
)
para("The platform has two halves, one per slide of the architecture deck:")
bullets([
    ("Slide 1 - Auto ML (model refresh): ", "a back-office pipeline that, weekly or on request, exports data from WBD Databricks into "
     "AWS, cleans it in a Bronze / Silver / Gold lakehouse (AWS Glue + Delta Lake on S3), trains and evaluates a model per business "
     "unit on Amazon SageMaker, registers it for human approval, writes model results into the database, and watches the model "
     "for drift every day."),
    ("Slide 2 - Optimization and explainable planning: ", "the planner-facing web application (UI + API on Amazon ECS Fargate) "
     "behind an internal load balancer with Okta sign-in. Heavy optimization runs are queued (SQS) and executed one container "
     "per run (Step Functions + ECS Fargate); results land in RDS PostgreSQL. In Release 2 every run also gets a plain-language "
     "explanation generated by Amazon Bedrock (Anthropic models by default), protected by Bedrock Guardrails."),
])
para("Cross-cutting 'control plane' bands on both slides: security (RBAC, SSO / MFA, IAM, KMS, Secrets Manager, security "
     "groups, VPC routes), data lineage and observability (CloudWatch, CloudTrail), the code repositories / CI/CD, Amazon "
     "Bedrock for GenAI and privacy & GenAI guardrails.")

table(
    ["Fact", "Value"],
    [
        ("Users", "50-150 planners at the same time during planning seasons; all on the WBD network (office, VPN, VDI)"),
        ("Environments", "3 WBD-owned AWS accounts: wbd-mmm-dev, wbd-mmm-stage, wbd-mmm-prod (name codes dev / stg / prd)"),
        ("Region", "us-east-1 (DR region us-west-2 only if WBD approves)"),
        ("Business units", "streaming, theatrical, usnetworks - data, keys, models and quotas are separated per BU"),
        ("Prescribed stack", "React + TypeScript (UI), Python / FastAPI + LangGraph (API), scikit-learn / XGBoost / SciPy (models and solver), RDS PostgreSQL + Databricks / S3, ECS"),
        ("Release 1 (go-live)", "Everything on both slides except the GenAI explanation (marked 'Not part of R1')"),
        ("Release 2", "GenAI explanation on Amazon Bedrock + Bedrock Guardrails, after WBD Responsible AI approval"),
        ("Who builds what", "WBD Infra creates the AWS resources with its own IaC from aws_resource_list_6.xlsx. WBD provides three code repositories (frontend, backend, data); their pipelines only deploy new images / code, never infrastructure."),
    ],
    widths=[4, 13],
)

# ------------------------------------------------------------------ 2
h("2. What changed in v6 (and what is deliberately NOT in the architecture)")
para("v6 is the final client architecture. Six changes compared with the previous version - each one is reflected in the resource list:")
table(
    ["#", "v6 requirement", "What it means for the infrastructure"],
    [
        ("1", "DNS/WAF + Route 53 removed - internal application",
         "No AWS WAF, no Route 53 hosted zone / record / resolver. The app name is a CNAME in WBD's internal DNS pointing to the internal ALB."),
        ("2", "Private access only - no public entry",
         "The Application Load Balancer is internal (scheme 'internal', in private subnets, no public IP). It is reachable only from the WBD network through the Transit Gateway. Its security group allows only WBD CIDR ranges - never 0.0.0.0/0."),
        ("3", "User authenticates with Okta first, then the ALB routes the request",
         "The ALB's HTTPS listener has Okta OIDC authentication as its first action. A request without a valid Okta session is redirected to Okta; nothing reaches the UI or API before sign-in."),
        ("4", "ECS inference & optimization: separate clusters or one?",
         "One ECS cluster per environment. It runs the ui and api services and, per optimization run, one Fargate task that executes Model Summarizer -> Optimizer -> Simulation in sequence. No separate clusters, no long-running optimizer services."),
        ("5", "Amazon API Gateway removed",
         "No API Gateway, no proxy Lambda, no execute-api endpoint. The API container calls Amazon Bedrock directly through a private bedrock-runtime VPC endpoint."),
        ("6", "LLM: Amazon Bedrock, Anthropic by default",
         "Anthropic Claude on Bedrock is the default model. OpenAI and Google models (served by Bedrock) are optional alternatives for experimentation. No external provider API keys - access is by IAM."),
    ],
    widths=[0.8, 5, 11.2],
)
para("Not in this architecture, so you will not find these in the resource list: Route 53, AWS WAF, a public / internet-facing "
     "load balancer, Amazon API Gateway, CloudFront, external LLM provider API keys, MWAA / Airflow, ElastiCache, separate ECS "
     "clusters for the optimizer.")

# ------------------------------------------------------------------ 3
h("3. Architecture overview")
h("3.1 The big picture", 2)
diagram(
    "                     WBD NETWORK (offices / VPN / VDI)                     OUTSIDE AWS\n"
    "   Planner browser ---- WBD internal DNS (mmm.<internal domain>)     Okta (SSO/MFA, groups)\n"
    "         |                                                             WBD Databricks (source)\n"
    "         |  Transit Gateway                                            Splunk (optional)\n"
    " ========|=================== AWS account wbd-mmm-<env> (us-east-1) ===========================\n"
    "  VPC 10.40.x.0/19                                                                          \n"
    "   private APP subnets                                                                      \n"
    "     Internal ALB (HTTPS 443, Okta sign-in first) --> ECS ui  (React)                       \n"
    "                                                  --> ECS api (FastAPI + LangGraph) --+      \n"
    "     ONE ECS cluster: ui + api services, migrate / platform-check tasks,             |      \n"
    "                      optimizer task per run (Summarizer -> Optimizer -> Simulation) |      \n"
    "     Lambdas: run dispatcher, results/data publisher, Databricks export trigger      |      \n"
    "     Glue job ENIs, SageMaker job ENIs                                               |      \n"
    "   private DATA subnets:  RDS Proxy --> RDS PostgreSQL (Multi-AZ stg/prd) <----------+      \n"
    "   private ENDPOINT subnets: interface endpoints (ECR, STS, KMS, Logs, SQS, Step Functions,\n"
    "                             Secrets Manager, SSM, SageMaker API, Glue, bedrock-runtime ...)\n"
    "   public subnets: NAT gateways only (outbound to Okta and Databricks) - nothing inbound    \n"
    "  Regional services (reached privately): S3 buckets, SQS, Step Functions, EventBridge,      \n"
    "   Glue Data Catalog, SageMaker (training, registry), Amazon Bedrock + Guardrails, CloudWatch\n"
    " ============================================================================================"
)
h("3.2 Slide 1 - Auto ML activities (model refresh)", 2)
diagram(
    " EventBridge (weekly schedule / manual mmm.refresh event / drift)\n"
    "     -> Step Functions 'model-refresh' (per business unit, waits + retries)\n"
    "         1 Lambda 'Export Trigger' (Databricks API connector) -> Databricks export job\n"
    "         2 Databricks writes raw Parquet -> S3 landing (write-only role)\n"
    "         3 Glue Bronze -> Silver (Data Quality) -> Gold   (Delta Lake on S3 lakehouse, Glue Data Catalog)\n"
    "         4 Glue exports: export-training -> S3 training-data (immutable)   export-rds -> S3 rds-export/\n"
    "         5 Lambda 'Results/data publisher' loads Gold reference data -> RDS PostgreSQL\n"
    "         6 SageMaker training (in the VPC) -> evaluation (baseline -> channel lift -> title adjustment)\n"
    "         7 SageMaker Model Registry (PendingManualApproval -> WBD approver) + lineage\n"
    "         8 Lambda 'Results/data publisher' writes predictions, lift, evaluation -> RDS PostgreSQL\n"
    " Daily: Step Functions 'model-monitor' -> drift job -> ModelDrift metric -> alarm (optional auto refresh)"
)
h("3.3 Slide 2 - Optimization and explainable planning", 2)
diagram(
    " Planner (WBD network) -> internal DNS -> Transit Gateway -> Internal ALB -> Okta sign-in FIRST\n"
    "     -> ECS ui (web app, QA dashboard)        -> ECS api (FastAPI + LangGraph tools)\n"
    " Upload inventory / future titles: browser --presigned PUT--> S3 uploads\n"
    " Run: api -> SQS optimization-requests -> Lambda message dispatcher (max concurrent runs)\n"
    "     -> Step Functions 'optimization' -> ECS Fargate inference & optimization task (one per run)\n"
    "            Model Summarizer -> Optimizer -> Simulation (reads approved curves + Model Registry)\n"
    "     -> S3 results (full run evidence) -> Lambda results publisher -> RDS (plans, runs, allocations)\n"
    " Release 2: api LangGraph explanation tool -> bedrock-runtime VPC endpoint -> Amazon Bedrock\n"
    "            (Anthropic default; OpenAI / Google optional) with Amazon Bedrock Guardrails on every call"
)

# ------------------------------------------------------------------ 4
h("4. Flow A - How a planner reaches the application (private entry, Okta first)")
para("Flow step S2-1. Resources: rows 44, 49, 57, 59, 80, 88, 134-139.")
steps([
    "The planner is on the WBD network (office LAN, VPN or VDI). There is no path from the internet.",
    "They open the internal app URL (e.g. https://mmm.<wbd internal domain>) or the 'WBD MMM' tile on their Okta dashboard. "
    "WBD internal DNS resolves the name (CNAME) to the internal ALB's DNS name, which resolves to private IPs in the MMM VPC.",
    "Traffic goes from the WBD network through the WBD Transit Gateway into the MMM VPC's private app subnets. The VPC "
    "route tables send the return traffic for the WBD ranges back through the Transit Gateway.",
    "The ALB security group accepts 443 (and 80, which only redirects to 443) from the WBD CIDR ranges only.",
    "The HTTPS listener terminates TLS with the certificate for the internal name (ACM DNS-validated certificate or a WBD "
    "private-CA certificate) and runs its first action, authenticate-oidc with Okta:",
    "No Okta session yet -> the ALB redirects the browser to Okta. The planner signs in with SSO + MFA. Okta redirects back to "
    "https://<internal name>/oauth2/idpresponse. The ALB exchanges the code for tokens by calling Okta's token and user-info "
    "endpoints - this is outbound from the ALB through the NAT gateway (or WBD central egress), which is why NAT is still needed "
    "although nothing is public.",
    "Signed in -> the ALB sets a session cookie (12 h) and forwards the request: /api/* to the api target group, everything "
    "else to the ui target group (port 8080, IP targets = ECS tasks). /api/health is the only path served without sign-in "
    "(health checks). Unauthenticated /api/* calls get 401.",
    "The ALB adds a signed header with the user's identity and Okta groups (mmm-bu-*, mmm-role-*). The API verifies the ALB "
    "signature and applies role-based access control; PostgreSQL row-level security restricts data to the user's business units.",
])
note("Engineers do not use this path for AWS access. They sign in to the AWS accounts through IAM Identity Center federated "
     "with Okta (permission sets ReadOnly, Developer, DevOps, Security, BreakGlass).")

# ------------------------------------------------------------------ 5
h("5. Flow B - An optimization or forecast run (slide 2)")
para("Flow steps S2-2 to S2-10. Resources: layers 09, 10, 11, 13.")
steps([
    ("Work in the UI (S2-2). ", "The ui service (React + TypeScript, QA dashboard) calls the api service (FastAPI). The API reads "
     "and writes plans, runs and allocations in RDS PostgreSQL through RDS Proxy (connection pooling, TLS, IAM authentication). "
     "Quick what-if simulations run synchronously inside the API (alarm if p95 > 10 s)."),
    ("Upload input (S2-3). ", "For 'Upload inventory + choose objective' or 'Upload future titles', the API returns a short-lived "
     "presigned URL. The browser uploads the file straight to the S3 uploads bucket under <bu>/runs/<run_id>/input/. The "
     "bucket's CORS allows only the internal app URL; objects expire after 90 days."),
    ("Queue the run (S2-4). ", "The API records the run as QUEUED in RDS and sends one message to the SQS queue "
     "mmm-<env>-optimization-requests (KMS-encrypted). After 10 failed attempts a message moves to the dead-letter queue (alarm). "
     "The queue absorbs planning-season bursts."),
    ("Dispatch (S2-5). ", "The 'message dispatcher' Lambda reads the queue and starts a Step Functions execution only while the "
     "number of running executions is below max_concurrent_runs (SSM parameter: 5 dev / 20 staging / 50 prod). Requests "
     "waiting more than 30 minutes are dropped and reported. Setting the value to 0 pauses new runs."),
    ("Run the inference & optimization container (S2-6). ", "The optimization state machine reads which optimizer task "
     "definition revision to use (SSM pointer written by the deploy pipeline) and starts ONE ECS Fargate task in the same ECS "
     "cluster (private subnet, no public IP, 4 vCPU / 16 GB, prod 8 vCPU / 32 GB, max 60 min). Inside that one container the "
     "three functions run in sequence: Model Summarizer -> Optimizer -> Simulation. It reads the uploaded file, the approved "
     "model (SageMaker Model Registry) and the approved response curves (S3 models bucket). It has no database access."),
    ("Store the evidence (S2-7). ", "The task writes the full run evidence (outputs, solver logs) to the S3 results bucket "
     "under runs/<run_id>/output."),
    ("Publish results (S2-8). ", "Step Functions invokes the results publisher Lambda, which loads plans, runs and allocations "
     "from S3 into RDS. The UI shows the finished run."),
    ("Explain (S2-9, Release 2). ", "See Flow C."),
    ("Approve and export (S2-10). ", "An approved scenario is written to the approved-worm bucket (S3 Object Lock - cannot be "
     "changed or deleted for 7 years, COMPLIANCE mode in prod). Excel exports go to the exports bucket (30-day expiry)."),
])
para("Why a queue + dispatcher + one task per run: optimizations are CPU-heavy and last seconds to minutes. One container per "
     "run isolates runs from each other and from the web tier, scales to zero between seasons, and the dispatcher caps "
     "concurrency so runs fit within the Fargate vCPU quota (prod >= 450 vCPU) and the database.")
note("Q4 in the decisions sheet: if the data scientists later need separate images for Summarizer / Optimizer / Simulation, "
     "they become three task definitions in the same cluster, chained by the same state machine - still one cluster.")

# ------------------------------------------------------------------ 6
h("6. Flow C - GenAI explanation on Amazon Bedrock (Release 2, 'Not part of R1')")
para("Flow step S2-9. Resources: rows 16, 17, 29, 54, 61, 92-95, 120, 194-198, 202.")
steps([
    "When a run completes, the API's LangGraph 'explanation tool' (invoked by default for every run) builds a prompt from the "
    "run results (no raw customer data beyond what the planner sees).",
    "It reads the model ID and guardrail ID / version from SSM Parameter Store (/mmm/<env>/genai/model_id, /genai/guardrail) "
    "and checks the business unit's daily token quota (/mmm/<env>/genai/token_quota/<bu>). The on/off switch is "
    "/mmm/<env>/genai_enabled (false in Release 1 - the run completes without an explanation).",
    "It calls the Bedrock Converse API with its ECS task role through the bedrock-runtime interface VPC endpoint "
    "('Amazon Runtime VPC Endpoint' on the slide) - the call never leaves the AWS network and needs no API key.",
    "Amazon Bedrock Guardrails are applied inside the same call to both the prompt and the answer: prompt-attack filter, "
    "content filters, PII masking / blocking, denied topics, contextual grounding and relevance checks (0.75).",
    "The answer is stored with the run and shown in the UI. Token use is published per BU (alarm at 80 % of the daily quota).",
])
para("How it is enforced without an API Gateway or proxy:")
bullets([
    "The API task role may invoke only the approved model / inference-profile IDs, and only when the request names the MMM "
    "guardrail (IAM condition bedrock:GuardrailIdentifier). A call without the guardrail is denied.",
    "The bedrock-runtime endpoint policy allows only this account's principals and the approved models.",
    "Model access in the account (WBD Cloud Platform): Anthropic first-time-use form; OpenAI / Google only if approved "
    "(AWS Marketplace subscription where needed). Prod: Anthropic only.",
    "Newer Claude models are offered through a US cross-region inference profile (requests may be served in us-east-1, "
    "us-east-2 or us-west-2) - the SCP must allow Bedrock in those regions.",
    "Optional: one application inference profile per BU (Bedrock cost and tokens reported per BU) and model invocation logging "
    "(metadata only unless WBD Privacy approves text logging).",
])
para("Alarms: bedrock-invocation-errors, bedrock-throttles (quota), bedrock-latency-p95 (> 30 s), "
     "genai-guardrail-interventions, genai-tokens-<bu>.")

# ------------------------------------------------------------------ 7
h("7. Flow D - Model refresh (slide 1, auto ML)")
para("Flow steps S1-1 to S1-11 and S1-13. Resources: layers 14-17.")
steps([
    ("Trigger (S1-1). ", "EventBridge Scheduler starts a refresh per business unit weekly (Monday 06:00 America/New_York; off "
     "until the data is ready), or an app / manual request sends the event mmm.refresh, or the drift check requests one. "
     "EventBridge starts the Step Functions state machine mmm-<env>-model-refresh (Wait / Retry built in)."),
    ("Export Trigger Lambda (S1-2). ", "The 'Databricks API connector' Lambda reads the Databricks service-principal "
     "credentials from Secrets Manager, gets an OAuth token and starts the BU's export job in WBD Databricks (Jobs API "
     "run-now), then polls it (runs/get). It reaches Databricks through NAT (NAT IPs on the Databricks IP access list) or "
     "optionally PrivateLink."),
    ("Raw data to S3 (S1-3). ", "The Databricks export job (owned by WBD Databricks admins) writes 3+ years of history as "
     "Parquet to s3://wbd-mmm-<env>-landing-use1/raw/databricks/<bu>/<date>/ through a Unity Catalog external location that "
     "uses a write-only IAM role. Each BU's data is encrypted with that BU's KMS key."),
    ("Bronze (S1-4). ", "Glue job bronze (Glue 5.0 Spark, Delta Lake) ingests the raw Parquet into Bronze Delta tables in the "
     "lakehouse bucket, registered in the Glue Data Catalog database mmm_<env>_bronze."),
    ("Silver (S1-5). ", "Glue job silver cleanses, conforms and validates with a Glue Data Quality ruleset. A failed rule stops "
     "the refresh and alerts."),
    ("Gold (S1-6). ", "Glue job gold builds the per-BU modeling tables (adstock, saturation)."),
    ("Exports (S1-7). ", "In parallel: export-training writes an immutable Parquet snapshot + metadata to the training-data "
     "bucket (Object Lock), so every model version can be reproduced; export-rds writes the Gold reference tables as Parquet "
     "to lakehouse/rds-export/<bu>/<refresh_id>/. Glue never connects to the database."),
    ("Reference data to RDS (S1-11, first part). ", "The 'Results/data publisher' Lambda loads the exported reference tables "
     "into RDS PostgreSQL through RDS Proxy. If this fails the refresh stops before training."),
    ("Training (S1-8). ", "A SageMaker training job (multi-stage model, ml.m5.2xlarge, in the VPC through SageMaker ENIs) reads "
     "the snapshot and writes the model artifact and drift baseline to the models bucket."),
    ("Evaluation (S1-9). ", "A SageMaker processing job evaluates baseline -> channel lift -> title adjustment and writes "
     "evaluation, predictions, lift and response curves."),
    ("Registration and approval (S1-10). ", "The version is registered in the SageMaker Model Registry (one model package group "
     "per BU) as PendingManualApproval. A governance pipeline checks the thresholds; a named WBD approver approves it, which "
     "publishes the approved response curves to the models bucket - the optimizer only ever uses approved curves."),
    ("Lineage (S1-13). ", "The refresh records where the data came from and what was produced: Databricks export run -> raw "
     "files -> Bronze / Silver / Gold table versions (Glue Data Catalog table properties) -> training snapshot -> training job "
     "-> model package (SageMaker ML Lineage Tracking). A lineage failure alarms but does not stop the refresh."),
    ("Model results to RDS (S1-11, second part). ", "The publisher writes the model's predictions, lift and evaluation results "
     "to RDS, tagged with the model package ARN, so the app shows them for the corresponding dataset."),
])
note("Glue orchestration is done by Step Functions (one Glue job run per layer), not by Glue workflows. Lake Formation is not "
     "used - access is controlled by IAM roles, bucket policies and per-BU KMS keys.")

# ------------------------------------------------------------------ 8
h("8. Flow E - Daily model drift monitoring")
para("Flow step S1-12. Resources: rows 174, 182, 190-193.")
steps([
    "EventBridge Scheduler starts mmm-<env>-model-monitor daily at 07:00 per business unit (switched on after the first "
    "approved model).",
    "Same front half as the refresh: Databricks export (purpose = monitor) -> Glue Bronze / Silver / Gold -> Glue export-monitor "
    "writes the latest features to lakehouse/monitoring/<bu>/<date>/.",
    "A SageMaker processing job compares them with the approved model's baseline and publishes the ModelDrift metric (0-1).",
    "Above 0.2 the alarm model-drift-<bu> fires. By default it is alert-only; automatic refresh (mmm.refresh event) can be "
    "switched on per WBD's decision.",
])

# ------------------------------------------------------------------ 9
h("9. Flow F - Releases and CI/CD (how code gets in)")
para("Flow step P-3. Resources: layer 04, 07, ECS / Lambda / Glue rows marked 'first version; new revisions by the deploy pipeline'.")
bullets([
    "WBD Infra creates every resource once (including the first task definitions, Lambdas and Glue jobs).",
    "WBD provides three repositories - frontend (ui), backend (api, publisher, LangGraph tools) and data (Glue scripts, DQ rules, "
    "training / optimizer images). Their pipelines log in to AWS with OpenID Connect (no stored keys) and assume narrow roles:",
    "  gha-ecr-push - push images to ECR (mmm/api, mmm/ui, mmm/optimizer, mmm/sagemaker-training; tags immutable, scanned).",
    "  gha-deploy - run the DB migration task, register new task-definition revisions, update the ECS services, move the SSM "
    "release pointers (optimizer task, training image), publish the publisher Lambda version / alias, upload Glue scripts.",
    "  gha-model-eval / gha-model-approve - model governance; approval in prod is done by a named WBD approver.",
    "  gha-plan / gha-apply - only if WBD decides to run Terraform from a pipeline (otherwise not created).",
    "Promotion: build once in dev; the same image digest is copied to staging (release candidate) and prod (release tag). Prod "
    "needs a WBD approver and a CAB change ticket. ECS deployments use a circuit breaker with automatic rollback.",
    "After each deploy a smoke test checks /api/health and the Okta redirect. Because the ALB is internal, this test must run "
    "from a runner inside the WBD network or the VPC (a self-hosted runner) - a cloud-hosted runner cannot reach it.",
])

# ------------------------------------------------------------------ 10
h("10. Network design")
h("10.1 VPC and subnets (per environment)", 2)
table(
    ["Subnet tier", "AZs (dev / stg / prd)", "What runs there", "Routes"],
    [
        ("Public", "2 / 3 / 3", "NAT gateways only - nothing inbound (the ALB is internal)", "0.0.0.0/0 -> Internet gateway"),
        ("Private app", "2 / 3 / 3", "Internal ALB, ECS tasks (ui, api, optimizer, migrate, platform-check), Lambdas (dispatcher, publisher, Databricks export), Glue ENIs, SageMaker ENIs",
         "0.0.0.0/0 -> NAT; WBD ranges -> Transit Gateway; S3 / DynamoDB gateway endpoints"),
        ("Private data", "2 / 3 / 3", "RDS PostgreSQL, RDS Proxy", "Local only (+ S3 gateway endpoint); no internet"),
        ("Private endpoint", "2 / 3 / 3", "Interface VPC endpoints", "Local only"),
    ],
    widths=[2.6, 2.8, 7, 4.6],
)
para("Proposed VPC CIDRs (WBD Network to confirm, no overlap with WBD ranges): dev 10.40.0.0/19, staging 10.40.32.0/19, prod "
     "10.40.64.0/19. NAT: 1 in dev, 1 per AZ in staging / prod (or WBD central egress through the Transit Gateway).")
h("10.2 Traffic paths", 2)
table(
    ["Path", "From -> To", "How"],
    [
        ("Planner access", "WBD network -> internal ALB", "Transit Gateway attachment in the app subnets; ALB SG allows only WBD CIDRs on 443 / 80"),
        ("Sign-in callback", "Internal ALB -> Okta", "Outbound HTTPS through NAT (or WBD egress) to *.okta.com"),
        ("Data export", "Export Lambda -> Databricks workspace API", "NAT (IPs on the Databricks IP access list) or optional Databricks PrivateLink"),
        ("Databricks -> S3", "Databricks export job -> landing bucket", "Databricks' own network to S3, using the write-only Unity Catalog IAM role"),
        ("AWS APIs", "Tasks / Lambdas / Glue / SageMaker -> AWS services", "Interface VPC endpoints (private DNS) and S3 / DynamoDB gateway endpoints - no internet"),
        ("GenAI", "API task -> Amazon Bedrock", "bedrock-runtime interface endpoint (endpoint policy: this account + approved models)"),
        ("Browser upload", "Planner browser -> S3 uploads", "HTTPS presigned PUT via WBD network egress (or an S3 interface endpoint if WBD requires private upload)"),
        ("Database", "api / migrate / publisher -> RDS", "5432 to RDS Proxy (data-clients SG) -> RDS (TLS required)"),
        ("Logs (optional)", "CloudWatch -> Splunk", "Kinesis Data Firehose to the WBD Splunk HEC endpoint"),
    ],
    widths=[3, 5, 9],
)
h("10.3 VPC endpoints", 2)
bullets([
    ("Gateway (free): ", "S3, DynamoDB."),
    ("Interface - core (13): ", "ecr.api, ecr.dkr, sts, kms, logs, monitoring, secretsmanager, ssm, ssmmessages, sqs, states "
     "(Step Functions), xray, sagemaker.api."),
    ("Interface - data platform: ", "glue."),
    ("Interface - Release 2: ", "bedrock-runtime."),
    ("Optional: ", "Databricks PrivateLink endpoint + private DNS zone for the workspace host."),
])
h("10.4 Security groups (least privilege)", 2)
table(
    ["Security group", "Attached to", "Inbound", "Outbound"],
    [
        ("alb", "Internal ALB", "443 + 80 from WBD CIDRs only", "8080 to ui / api SGs; 443 to Okta via NAT"),
        ("ui", "ECS ui tasks", "8080 from alb", "443 to endpoints / S3"),
        ("api", "ECS api tasks", "8080 from alb", "443 to endpoints (incl. bedrock-runtime), S3, ALB signing keys"),
        ("data-clients", "api, migrate, publisher", "-", "5432 to rds-proxy; 443 to endpoints / S3"),
        ("rds-proxy", "RDS Proxy", "5432 from data-clients", "5432 to rds"),
        ("rds", "RDS PostgreSQL", "5432 from rds-proxy only", "-"),
        ("optimizer", "Optimizer tasks", "none", "443 to endpoints / S3 only (no database)"),
        ("lambda", "Dispatcher, publisher", "none", "443 to endpoints / S3 (+ data-clients for DB)"),
        ("tasks", "migrate, platform-check", "none", "443 to endpoints, S3, package indexes"),
        ("databricks-export", "Export Lambda", "none", "443 to Databricks (NAT / PrivateLink) and endpoints"),
        ("glue", "Glue job ENIs", "self (Spark driver <-> executors)", "443 to endpoints / S3"),
        ("sagemaker", "Training / processing ENIs", "self (distributed training)", "443 to endpoints / S3"),
        ("endpoints", "Interface endpoints", "443 from the VPC CIDR", "-"),
    ],
    widths=[2.8, 3.6, 4.2, 6.4],
    font=8.5,
)

# ------------------------------------------------------------------ 11
h("11. Security, identity and data protection")
bullets([
    ("Accounts and baseline (WBD-owned, verified): ", "separate account per environment; SCPs; CloudTrail organization trail; "
     "GuardDuty; Security Hub; AWS Config; Inspector (ECR image scanning); IAM Access Analyzer; S3 Block Public Access and EBS "
     "encryption by default at account level."),
    ("People: ", "planners sign in through Okta at the internal ALB (groups drive RBAC). Engineers use IAM Identity Center "
     "federated with Okta - no IAM users or access keys. BreakGlass use raises an alert."),
    ("Machines: ", "'AWS IAM' on every arrow of the slides = one least-privilege IAM role per integration (each ECS task, "
     "Lambda, state machine, Glue, SageMaker, pipeline). Every role carries the permission boundary mmm-<env>-permission-boundary, "
     "which caps what any role can do (no IAM users / keys, approved regions only, cannot disable security services)."),
    ("Encryption: ", "'KMS' on every store = customer-managed keys with rotation per purpose (s3, rds, logs, secrets, ecr, sqs, "
     "sagemaker, alerts, backup, genai) plus one S3 key per business unit (streaming, theatrical, usnetworks) for BU data isolation "
     "in landing, lakehouse and training-data. TLS everywhere (bucket policies deny non-TLS; RDS force_ssl; ALB TLS 1.3 policy)."),
    ("Secrets: ", "Secrets Manager under mmm/<env>/... (DB users, Okta ALB client secret, Databricks service principal, optional "
     "Splunk HEC and vendor keys). Values are entered by the owning team, never by email or in Git. The RDS admin password is "
     "managed and rotated by RDS. Non-secret settings live in SSM Parameter Store under /mmm/<env>/..."),
    ("Data: ", "PostgreSQL row-level security per BU; S3 Object Lock for training snapshots and approved scenarios; CloudWatch Logs "
     "data protection policy masks personal data; optional Macie and GuardDuty Malware Protection for uploads."),
    ("GenAI: ", "Bedrock runs inside AWS (no data sent to external LLM APIs); guardrail mandatory via IAM; written Responsible AI "
     "approval required before Release 2."),
])

# ------------------------------------------------------------------ 12
h("12. Operations: monitoring, logging, backup and cost")
bullets([
    ("CloudWatch everywhere: ", "logs for every component (30 / 90 / 365 days in dev / staging / prod, KMS-encrypted), Container "
     "Insights on the ECS cluster, 8 dashboards (platform, api-ui, optimization, rds, cost, data-pipeline, training, genai)."),
    ("Alerts: ", "every alarm and EventBridge alert rule goes to the SNS topic mmm-<env>-alerts (email / on-call)."),
    ("Audit: ", "CloudTrail org trail for management events, plus S3 data events on the 7 MMM data buckets (WBD org trail "
     "selectors); VPC flow logs; ECS Exec sessions recorded."),
    ("Splunk (optional): ", "Kinesis Data Firehose ships all log groups to WBD Splunk; failed records go to the logs bucket."),
    ("Backup / DR: ", "AWS Backup daily for RDS and the data buckets tagged backup = true (7 / 14 / 35 days; prod monthly kept "
     "1 year; vault lock in prod if approved); RDS point-in-time restore; optional cross-region copy to us-west-2. Proposed RPO "
     "24 h (RDS PITR ~5 min), RTO 4 h."),
    ("Cost: ", "monthly budget per account (3,000 / 6,000 / 15,000 USD proposed) with 50 / 80 / 100 % emails and a daily cost "
     "anomaly monitor."),
])
h("12.1 Alarms and alert rules (46 in total)", 2)
table(
    ["Area", "Alarms / rules", "Fires when (summary)"],
    [
        ("Web app", "api-5xx-rate, availability, api/ui-no-healthy-targets, cert-expiry-alb, whatif-p95", "5xx > 2 %, availability < 99.5 %/h, no healthy task, certificate < 30 days, what-if p95 > 10 s"),
        ("Optimization", "optimization-failed / -throttled / -runtime-max / -standard-p95, results-publisher-errors", "Run failed, throttled, > 10 min, p95 > 120 s, publisher errors"),
        ("Run queue", "runs-oldest-request, runs-expired-requests, runs-dlq-not-empty, runs-dispatcher-errors / -throttles", "Waiting > 15 min, dropped after 30 min, DLQ not empty, dispatcher failing"),
        ("Database", "rds-cpu, rds-connections, rds-free-storage, rds-read/write-latency", "CPU > 80 %, connections > 80 %, < 20 GiB free, latency > 20 ms"),
        ("Model refresh", "model-refresh-failed / -throttled / -overdue, databricks-export-errors, lineage-record-failed-<bu>", "Refresh failed, none succeeded in 7 days, export Lambda failing, lineage not recorded"),
        ("Drift", "model-monitor-failed / -throttled, model-drift-<bu>", "Monitor failed, drift > 0.2"),
        ("GenAI (R2)", "bedrock-invocation-errors, bedrock-throttles, bedrock-latency-p95, genai-guardrail-interventions, genai-tokens-<bu>", "Bedrock errors > 5 / 5 min, throttling, p95 > 30 s, > 25 blocks / 15 min, 80 % of daily tokens"),
        ("Event rules", "guardduty-high, breakglass-used, ecs-deployment-failed, ecs-service-error, optimizer-task-not-started, backup-job-failed, glue-job-failed, glue-data-quality-failed, model-package-state", "Security finding >= 7, break-glass, failed deploy / task start, backup / Glue / DQ failure, model version state change"),
        ("Splunk (opt.)", "splunk-delivery, splunk-freshness", "Delivery failing, data older than 15 min"),
    ],
    widths=[2.5, 7, 7.5],
    font=8.5,
)

# ------------------------------------------------------------------ 13
h("13. Complete AWS service list")
para("Every AWS service the platform uses, what it does here and where it appears in the resource list.")
table(
    ["AWS service", "Used for", "Layer(s)"],
    [
        ("AWS Organizations / SCPs", "One account per environment; service and region guardrails", "01"),
        ("IAM Identity Center", "Engineer SSO with Okta; permission sets", "01"),
        ("AWS IAM", "Least-privilege role per integration, permission boundary, GitHub OIDC provider and pipeline roles", "04, all"),
        ("AWS KMS", "Customer-managed keys per purpose + per business unit", "02, 03"),
        ("AWS Secrets Manager", "DB users, Okta ALB client secret, Databricks service principal, optional Splunk / vendor keys", "08"),
        ("SSM Parameter Store", "Settings and release pointers (max concurrent runs, optimizer task, training image, Okta issuer, Databricks job IDs, GenAI model / guardrail / quotas)", "08"),
        ("Amazon VPC", "VPC, 4 subnet tiers, route tables, IGW, NAT, gateway + interface endpoints, security groups, flow logs", "05, 06"),
        ("AWS Transit Gateway", "The only way in: WBD network -> internal ALB (attachment owned by MMM, TGW by WBD)", "05"),
        ("Elastic Load Balancing (ALB)", "Internal ALB, HTTPS listener with Okta OIDC, path rules, target groups", "12"),
        ("AWS Certificate Manager", "TLS certificate for the internal app name (or WBD private CA)", "12"),
        ("Amazon ECR", "Images api, ui, optimizer, sagemaker-training; enhanced scanning", "07"),
        ("Amazon ECS on AWS Fargate", "One cluster: ui + api services, migrate / platform-check tasks, one optimizer task per run", "11, 13"),
        ("AWS Cloud Map", "Service Connect namespace inside the cluster", "11"),
        ("Application Auto Scaling", "CPU target tracking (60 %) for api and ui", "11"),
        ("Amazon RDS for PostgreSQL + RDS Proxy", "System of record: plans, runs, allocations, Gold reference data, model results; RLS per BU", "10"),
        ("Amazon S3", "10 buckets: logs, landing, lakehouse, training-data, glue-assets, models, uploads, results, approved-worm, exports (+ Terraform state if used)", "09"),
        ("Amazon SQS", "Optimization request queue + dead-letter queue", "13"),
        ("AWS Lambda", "Run dispatcher, results/data publisher, Databricks Export Trigger", "13, 14"),
        ("AWS Step Functions", "State machines optimization, model-refresh, model-monitor", "13, 17"),
        ("Amazon EventBridge + EventBridge Scheduler", "Refresh / drift schedules, on-demand refresh event, alert rules, S3 notifications", "17, 19"),
        ("AWS Glue (+ Data Catalog, Data Quality)", "Bronze / Silver / Gold Delta jobs, exports, catalog databases, Silver DQ ruleset, lineage properties", "15"),
        ("Amazon SageMaker", "Training and processing jobs (in the VPC), Model Registry per BU, ML Lineage Tracking", "16"),
        ("Amazon Bedrock + Bedrock Guardrails", "Release 2 explanation: Anthropic default, OpenAI / Google optional; guardrail; optional inference profiles and invocation logging", "18"),
        ("Amazon CloudWatch (Logs, metrics, alarms, dashboards, Container Insights)", "Observability on every component; logs data protection policy", "19"),
        ("Amazon SNS", "Alert topic", "19"),
        ("Amazon Kinesis Data Firehose", "Optional log shipping to Splunk", "19"),
        ("AWS CloudTrail", "Org trail (management events) + S3 data events on the MMM buckets", "01"),
        ("Amazon GuardDuty, Security Hub, AWS Config, Amazon Inspector, IAM Access Analyzer, Amazon Macie (opt.)", "Account security baseline (WBD-owned, verified)", "01"),
        ("AWS Backup", "Vault, daily plan, tag-based selection, optional DR vault + cross-region copy", "20"),
        ("AWS Budgets + Cost Anomaly Detection", "Monthly budget and anomaly alerts", "04"),
        ("Service Quotas", "Fargate vCPU, Glue, SageMaker, Bedrock tokens", "01"),
        ("Amazon DataZone / SageMaker Catalog (optional)", "Visual lineage graph and business catalog", "15"),
    ],
    widths=[5, 9.8, 2.2],
    font=8.5,
)

h("13.1 Resource count per layer (from the summary sheet)", 2)
table(
    ["Layer", "Rows", "R1", "R2", "AWS objects (prod)", "Main resources"],
    [
        ("01 Account baseline", 18, 17, 1, 3, "Accounts, SCPs, Identity Center, CloudTrail, GuardDuty, Security Hub, Config, Inspector, quotas, Bedrock model access"),
        ("02 Terraform state", 2, 2, 0, 2, "State bucket + key (only if WBD runs Terraform)"),
        ("03 Encryption (KMS)", 12, 11, 1, 14, "Purpose keys + 3 BU keys + genai key"),
        ("04 IAM and CI/CD access", 10, 10, 0, 11, "Permission boundary, OIDC provider, pipeline roles, budget, anomaly monitor"),
        ("05 Networking", 16, 15, 1, 48, "VPC, subnets, IGW, NAT, routes, endpoints, flow logs, TGW attachment"),
        ("06 Security groups", 13, 13, 0, 13, "One SG per component"),
        ("07 ECR", 5, 5, 0, 5, "4 repositories + scanning"),
        ("08 Secrets and parameters", 19, 15, 4, 21, "Secrets + SSM parameters"),
        ("09 Storage (S3)", 11, 11, 0, 11, "10 buckets + optional malware scan"),
        ("10 Database", 8, 8, 0, 12, "RDS PostgreSQL, Proxy, groups, logs, DB users"),
        ("11 ECS UI and API", 19, 19, 0, 22, "Cluster, task definitions, services, roles, logs, scaling"),
        ("12 Front door and sign-in (internal)", 6, 6, 0, 9, "Certificate, internal ALB, listeners, rules, target groups, Okta app"),
        ("13 Optimization engine", 16, 16, 0, 16, "SQS + DLQ, dispatcher, state machine, optimizer task, publisher"),
        ("14 Databricks export", 6, 6, 0, 10, "UC role, export Lambda, Databricks jobs and service principal"),
        ("15 Glue lakehouse", 15, 15, 0, 16, "Catalog, security config, connection, 6 jobs, DQ ruleset, lineage"),
        ("16 SageMaker modeling", 6, 6, 0, 6, "Role, model package groups, job logs (jobs created at run time)"),
        ("17 Refresh and drift orchestration", 11, 11, 0, 18, "2 state machines, schedules, event rules"),
        ("18 GenAI on Bedrock (R2)", 5, 3, 2, 10, "Models, inference profiles, guardrail, invocation logging"),
        ("19 Monitoring and logging", 11, 10, 1, 82, "SNS, alarms, event rules, dashboards, Firehose, subscriptions"),
        ("20 Backup and DR", 5, 5, 0, 9, "Vault, plan, selection, DR vault"),
        ("Total", 214, 204, 10, 338, ""),
    ],
    widths=[4.2, 1.1, 1, 1, 2, 7.7],
    font=8.5,
)
para("Scope of the 214 rows: 115 Required, 49 Required for the model refresh / data platform, 10 Required for GenAI (after "
     "WBD approval), 20 Optional (only if WBD approves), 11 account baseline to verify, 4 quota requests, 5 created at run time.")

h("13.2 Sizing per environment", 2)
table(
    ["Item", "dev", "staging", "prod"],
    [
        ("Availability Zones / NAT gateways", "2 / 1", "3 / 3", "3 / 3"),
        ("api tasks (1 vCPU / 2 GB)", "1-2", "2-4", "3-10"),
        ("ui tasks (0.25 vCPU / 0.5 GB)", "1-2", "2-3", "2-6"),
        ("Optimizer task size", "4 vCPU / 16 GB", "4 vCPU / 16 GB", "8 vCPU / 32 GB"),
        ("Concurrent optimization runs", "5", "20", "50"),
        ("Fargate vCPU quota", ">= 40", ">= 120", ">= 450"),
        ("RDS PostgreSQL 16", "db.t4g.medium, single-AZ, 50 GB", "db.r6g.large, Multi-AZ, 100 GB", "db.r6g.xlarge, Multi-AZ, 200 GB"),
        ("RDS point-in-time restore", "7 days", "14 days", "35 days"),
        ("Glue workers (G.1X)", "2", "5", "10"),
        ("SageMaker", "ml.m5.2xlarge training, ml.m5.xlarge evaluation / drift (all environments)", "", ""),
        ("Log retention", "30 days", "90 days", "365 days"),
        ("Monthly budget (proposed)", "3,000 USD", "6,000 USD", "15,000 USD"),
        ("Bedrock (R2)", "Anthropic (+ optional OpenAI / Google)", "Anthropic (+ optional)", "Anthropic only; >= 200,000 tokens / min"),
    ],
    widths=[5, 4, 4, 4],
)

h("13.3 Naming conventions", 2)
bullets([
    "Resources: mmm-<env>-<purpose> (env = dev / stg / prd), e.g. mmm-prd-alb, mmm-stg-optimization.",
    "Buckets: wbd-mmm-<env>-<purpose>-use1, e.g. wbd-mmm-dev-landing-use1.",
    "Secrets: mmm/<env>/<path>; SSM parameters: /mmm/<env>/<path>; KMS aliases: alias/mmm-<env>-<purpose>; Glue databases: mmm_<env>_<layer>.",
    "Tags on every resource: Project, Environment, Owner, CostCenter, ManagedBy; backup = true on backed-up resources.",
])

# ------------------------------------------------------------------ 14
h("14. What other WBD teams provide (outside AWS)")
table(
    ["Team", "Provides", "Needed before"],
    [
        ("WBD Network", "VPC CIDRs, AZ IDs, Transit Gateway ID + route-table association / propagation (RAM share), the WBD CIDRs allowed to reach the internal ALB, egress for Okta and Databricks", "Networking - the app is only reachable through the TGW"),
        ("WBD DNS / PKI", "Internal app name per environment (CNAME to the internal ALB) + certificate (ACM DNS validation records or WBD private CA)", "The HTTPS listener"),
        ("WBD Identity (Okta)", "Okta OIDC app per environment, groups mmm-bu-* / mmm-role-*, client secret into Secrets Manager; Identity Center federation", "Sign-in is switched on"),
        ("WBD Databricks admins", "Export job per BU, service principal + OAuth secret, Unity Catalog storage credential + external location, IP access list (NAT IPs) or PrivateLink", "First model refresh"),
        ("WBD Cloud Platform", "Quota increases, SCP allow-list (incl. Bedrock profile regions), Bedrock model access", "Load test / first refresh / Release 2"),
        ("WBD repository owners", "Frontend, backend and data repositories, pipeline environments and approvers, OIDC trust subjects", "First deploy"),
        ("Data engineers / data science / backend", "Glue scripts + DQ rules; optimizer and training images; DB migrations, row-level security, publisher code", "First run / refresh / go-live"),
        ("WBD Security / Audit", "CloudTrail S3 data-event selectors on the MMM buckets", "Production data arrives"),
        ("WBD Splunk (optional)", "HEC endpoint, token, index", "Only if Splunk shipping is required"),
    ],
    widths=[3.5, 9.5, 4],
)

# ------------------------------------------------------------------ 15
h("15. Key decisions to confirm with WBD")
para("The full list is the decisions_to_confirm sheet (Q1-Q36). The ones the infra team is most likely to discuss:")
table(
    ["#", "Question", "Proposed default"],
    [
        ("Q1", "How do planners reach the app?", "Internal ALB in private subnets, only from the WBD network through the Transit Gateway"),
        ("Q2", "Internal DNS and certificate?", "CNAME in WBD internal DNS; ACM certificate if under a public WBD domain, else WBD private CA"),
        ("Q3", "Okta first, then the ALB?", "Yes - authenticate-oidc is the first listener action; ALB reaches Okta through NAT"),
        ("Q4", "Separate ECS clusters for the three inference functions?", "No - one cluster; one task per run runs Summarizer -> Optimizer -> Simulation"),
        ("Q5-Q7", "Bedrock without API Gateway; models; guardrail enforcement", "Direct Converse via bedrock-runtime endpoint; Anthropic default, OpenAI / Google optional; IAM condition forces the guardrail"),
        ("Q8", "Cross-region inference profile?", "US profile where the model needs it (SCP must allow the regions)"),
        ("Q10", "Does Glue write to RDS?", "No - Glue writes Parquet; the results/data publisher Lambda loads RDS"),
        ("Q13", "Lambdas inside or outside the VPC?", "Inside (private subnets) - the publisher must reach RDS Proxy privately"),
        ("Q16 / Q17", "CloudTrail / CloudWatch 'across all components'", "WBD org trail + S3 data events; logs, metrics and alarms on every component"),
        ("Q20", "GenAI timing", "Release 2; switched off in Release 1"),
        ("Q34", "Self-hosted runners?", "Builds on hosted runners; the post-deploy smoke test needs a runner on the WBD network (internal ALB)"),
        ("Q35 / Q36", "Who creates resources; what pipelines deploy", "WBD Infra with its own IaC; pipelines deploy images, task revisions, Lambda code and Glue scripts only"),
    ],
    widths=[1.4, 6, 9.6],
)
para("Most important inputs WBD provides first (client_inputs sheet): account IDs, region / SCP confirmation, VPC CIDRs and "
     "Transit Gateway details, the WBD CIDRs for the ALB, internal app names + certificate, Okta app details, the three "
     "repository names, quotas, KMS / IAM standards, and for the data platform the Databricks workspace, jobs and service principal.")

# ------------------------------------------------------------------ 16
h("16. Questions the infra team is likely to ask")
faq = [
    ("Why do we still need NAT gateways and an internet gateway if nothing is public?",
     "They are outbound only. The ALB must call Okta's token / user-info endpoints during sign-in, and the export Lambda calls the "
     "Databricks workspace API. Nothing can connect inbound. If WBD offers central egress through the Transit Gateway, the public "
     "subnets, IGW and NAT can be dropped."),
    ("Can the ALB use a WBD proxy to reach Okta?",
     "No - the ALB's OIDC client cannot be configured with a proxy; it needs direct HTTPS egress (NAT or routed egress) to *.okta.com."),
    ("Why is there no WAF?",
     "The app is internal: only WBD ranges can reach it through the Transit Gateway, and every request must pass Okta sign-in first. "
     "WBD removed DNS/WAF + Route 53 in v6."),
    ("Why one ECS cluster?",
     "A cluster is only a logical grouping on Fargate; it costs nothing and has no capacity of its own. ui and api are long-running "
     "services, the optimizer is a short-lived task per run - all separated by their own task roles, security groups and scaling. "
     "Separate clusters would add operational overhead without isolation benefit."),
    ("How does the browser upload files to S3 if the app is internal?",
     "The browser PUTs directly to the S3 uploads bucket with a presigned URL (valid minutes, scoped to the user's BU prefix). It uses "
     "the WBD network's normal path to S3. If WBD requires uploads to stay private, an S3 interface endpoint reachable through the "
     "Transit Gateway can be added."),
    ("Does any data leave AWS for GenAI?",
     "No. Bedrock runs the Anthropic (and optional OpenAI / Google) models inside AWS; the API reaches it through a VPC endpoint. "
     "With a cross-region inference profile, requests may be processed in another US region."),
    ("Who can deploy what?",
     "WBD Infra creates and changes infrastructure. The three repository pipelines only push images and deploy new revisions of "
     "existing ECS tasks / services, Lambda code and Glue scripts, using OIDC roles scoped to the repository and environment."),
    ("What must exist before the first deploy?",
     "Layers 01-12 (accounts, keys, IAM, network + TGW, SGs, ECR, secrets, buckets, RDS, ECS, internal ALB with certificate and "
     "Okta) and layer 13 for optimization. Layers 14-17 for the model refresh can follow; layer 18 only for Release 2."),
    ("How are business units isolated?",
     "Per-BU KMS keys and S3 prefixes for data, a model package group per BU, per-BU token quotas, Okta groups mmm-bu-* for RBAC and "
     "PostgreSQL row-level security."),
    ("What happens if an optimization run fails?",
     "Step Functions retries transient errors; the run is marked failed in RDS and the optimization-failed alarm fires. A request that "
     "cannot be dispatched 10 times lands in the DLQ (runs-dlq-not-empty) and can be redriven."),
]
for q, a in faq:
    p = d.add_paragraph()
    r = p.add_run("Q: " + q)
    r.bold = True
    p.paragraph_format.space_after = Pt(0)
    p = d.add_paragraph("A: " + a)
    p.paragraph_format.space_after = Pt(6)

# ------------------------------------------------------------------ 17
h("17. Glossary")
table(
    ["Term", "Meaning"],
    [
        ("MMM", "Media-mix modeling - estimates how each marketing channel drives results"),
        ("Adstock / saturation", "Carry-over effect of advertising over time / diminishing returns of spend"),
        ("Response curve", "Approved model output per channel used by the optimizer to allocate budget"),
        ("BU", "Business unit: streaming, theatrical, usnetworks"),
        ("Bronze / Silver / Gold", "Lakehouse layers: raw ingested / cleansed and validated / modeling-ready per BU"),
        ("Delta Lake", "Open table format on S3 used by the Glue jobs (versioned tables)"),
        ("Drift", "Change of recent data compared with the data the model was trained on"),
        ("Internal ALB", "Load balancer with private IPs only, reachable from inside the VPC / connected networks"),
        ("OIDC", "OpenID Connect - used by the ALB (Okta sign-in) and by pipelines (keyless AWS login)"),
        ("Transit Gateway", "WBD's network hub that connects VPCs and on-premises / VPN networks"),
        ("Guardrail", "Amazon Bedrock policy applied to prompts and answers (PII, topics, grounding, prompt attacks)"),
        ("Inference profile", "Bedrock object that routes a model across regions (cross-region) or tags usage (per BU)"),
        ("R1 / R2", "Release 1 go-live / Release 2 GenAI explanation"),
    ],
    widths=[4, 13],
)

out = Path(sys.argv[1] if len(sys.argv) > 1 else ".") / OUT
d.save(out)
print("written", out)

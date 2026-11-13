"""Builds the requirement 5 documents (WBD_MMM_Architecture_5.pptx):

- aws_resource_list_5.xlsx: complete AWS resource list for the WBD infrastructure team (same layout as
  aws_resource_list_4_new.xlsx) - name per environment, what it does in the v5 flow, settings per environment, Release,
  owner - plus 'Change vs v4' (the v4 build is in the repo) and the sheets v5_changes / removed_vs_v4.
- devops_5_client_question.xlsx: all inputs and decisions WBD has to provide for v5, by layer of aws_resource_list_5.xlsx
  (--questions-only rebuilds just this workbook).
- wbd_mmm_ecs_final_5.docx: v5 design document.

Usage: uv run --no-project --with openpyxl --with python-docx python build_v5.py <docs/requirements>
"""
import sys
from pathlib import Path

import docx
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Pt, RGBColor
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent

ENVS = (("dev", "dev", "Dev"), ("staging", "stg", "Staging"), ("prod", "prd", "Prod"))
BUS = "streaming, theatrical, usnetworks"

CORE = "Required"
DP = "Required - model refresh / data platform"
GENAI = "Required for GenAI (create after WBD approval)"
OPT = "Optional - only if WBD approves"
BASE = "Account baseline - verify it exists"
RUN = "Not pre-created - created at run time"
QUOTA = "Quota request"

INFRA = "WBD Infra"
INFRA_PIPE = "WBD Infra (first version); new revisions by the deploy pipeline"
PLAT = "WBD Cloud Platform"
SEC = "WBD Security"
IDN = "WBD Identity (Okta)"
DNS = "WBD DNS / PKI"
DBX = "WBD Databricks admins"
DS = "Data science (image) - started by Step Functions"
APPT = "Backend team (via the migrate task)"


def s(dev, stg=None, prd=None):
    """Value per environment; one argument = same in all three."""
    return (dev, dev if stg is None else stg, dev if prd is None else prd)


ALL1 = s("1")

# Flow steps referenced in the 'Flow step' column; full text on the architecture_flow sheet.
FLOW = [
    ("S1-1", "Slide 1 - Auto ML", "Trigger", "A model refresh starts for one business unit: weekly schedule (EventBridge Scheduler), manual / app request (EventBridge event mmm.refresh) or the drift check. EventBridge starts the Step Functions state machine model-refresh."),
    ("S1-2", "Slide 1 - Auto ML", "Export Trigger Lambda (Databricks API connector)", "Step Functions invokes the 'Lambda Functions - Export Trigger' (mmm-<env>-databricks-export). It reads the Databricks service principal from Secrets Manager, gets an OAuth token and starts the export job of the business unit in the WBD Databricks source catalog (Jobs API run-now), then polls it (runs/get)."),
    ("S1-3", "Slide 1 - Auto ML", "Raw data to S3", "The Databricks export job writes 3+ years of history as Parquet to s3://landing/raw/databricks/<bu>/<date>/ through a Unity Catalog external location on a write-only IAM role. The Lambda writes _manifest.json."),
    ("S1-4", "Slide 1 - Auto ML", "AWS Glue - Bronze", "Glue job bronze ingests the raw Parquet into Bronze Delta tables (lakehouse bucket, Glue Data Catalog database bronze)."),
    ("S1-5", "Slide 1 - Auto ML", "AWS Glue - Silver", "Glue job silver cleanses and validates the data (Glue Data Quality ruleset); a failed rule stops the refresh and alerts."),
    ("S1-6", "Slide 1 - Auto ML", "AWS Glue - Gold", "Glue job gold builds the per-business-unit modeling tables (adstock, saturation) - Delta Lake storage on S3."),
    ("S1-7", "Slide 1 - Auto ML", "Glue exports", "export-training writes an immutable Parquet snapshot to the training-data bucket (Object Lock); export-rds writes the Gold reference tables as Parquet to the lakehouse bucket (rds-export/<bu>/<refresh_id>/). Glue has no database access."),
    ("S1-8", "Slide 1 - Auto ML", "SageMaker training (in the VPC)", "SageMaker training job (multi-stage model) reads the training data and writes the model artifact to the models bucket."),
    ("S1-9", "Slide 1 - Auto ML", "SageMaker evaluation", "SageMaker processing job evaluates the model: baseline -> channel lift -> title adjustment; writes evaluation, predictions, lift and response curves."),
    ("S1-10", "Slide 1 - Auto ML", "Model registration", "The model version is registered in the SageMaker Model Registry (group per business unit, PendingManualApproval). A named WBD approver approves it; approved curves are published to the models bucket."),
    ("S1-11", "Slide 1 - Auto ML", "Results / data written to RDS", "The 'Results/data publisher' Lambda loads the Glue Gold export (reference data) and writes the model predictions, lift and evaluation results to RDS PostgreSQL through RDS Proxy."),
    ("S1-12", "Slide 1 - Auto ML", "Model drift monitoring", "Daily schedule per business unit starts model-monitor: Databricks export + Glue layers + export-monitor -> SageMaker drift job -> ModelDrift metric and alarm (optional automatic refresh)."),
    ("S1-13", "Slide 1 - Auto ML", "Lineage", "'AWS Glue + Data Catalog (Lineage)' and 'Registry + S3 ... + lineage': every refresh records where the data came from (Databricks export run, Glue job runs, Delta table versions, training-data snapshot) and which model version was trained from it (SageMaker ML Lineage Tracking)."),
    ("S2-1", "Slide 2 - Optimization", "Sign-in", "Planner opens the app: Route 53 / WBD DNS -> AWS WAF -> public Application Load Balancer (HTTPS, ACM certificate) -> Okta sign-in at the ALB (authentication, groups for RBAC)."),
    ("S2-2", "Slide 2 - Optimization", "UI and API on ECS", "ECS Fargate service ui (React + TypeScript, QA dashboard) and service api (Python FastAPI + LangGraph tools) in private subnets; API reads / writes plans, runs and allocations in RDS PostgreSQL through RDS Proxy."),
    ("S2-3", "Slide 2 - Optimization", "Upload inventory / future titles", "The API returns a presigned URL; the browser uploads the input file straight to the S3 uploads bucket (user input files)."),
    ("S2-4", "Slide 2 - Optimization", "Queue the run", "The API stores the run as QUEUED and sends a message to the SQS queue optimization-requests (dead-letter queue after 10 failures)."),
    ("S2-5", "Slide 2 - Optimization", "Message dispatcher", "The dispatcher Lambda reads the queue and starts a Step Functions optimization execution while fewer than max_concurrent_runs are running."),
    ("S2-6", "Slide 2 - Optimization", "ECS inference & optimization", "Step Functions runs one ECS Fargate optimizer task per run (Model Summarizer -> Optimizer -> Simulation). It reads the input file, the approved model (Model Registry) and the approved response curves (S3)."),
    ("S2-7", "Slide 2 - Optimization", "S3 outputs", "The optimizer writes the full run evidence to the results bucket (runs/<run_id>/output)."),
    ("S2-8", "Slide 2 - Optimization", "Results publisher", "Step Functions invokes the results publisher Lambda, which writes plans, runs and allocations to RDS PostgreSQL. The UI shows the result."),
    ("S2-9", "Slide 2 - Optimization", "Explanation (GenAI) - not part of R1", "Release 2 (slide 2 marks the box 'Not part of R1'): the API's LangGraph explanation tool calls the private API Gateway LLM gateway -> proxy Lambda -> Amazon Bedrock Guardrails -> OpenAI / Anthropic / Google models. In Release 1 the run completes without the explanation."),
    ("S2-10", "Slide 2 - Optimization", "Approve / export", "Approved scenarios are stored immutably in the approved-worm bucket (Object Lock); Excel exports go to the exports bucket (30-day expiry)."),
    ("P-1", "Platform", "Security", "Accounts, IAM roles, KMS keys, Secrets Manager / Parameter Store, security groups, VPC endpoints - used by every step above."),
    ("P-2", "Platform", "Logging / Operations", "Environment-level components 'enabled across all components': CloudWatch logs, metrics, alarms, dashboards, EventBridge alert rules, SNS alerts, CloudTrail (management + S3 data events), optional shipping to Splunk."),
    ("P-3", "Platform", "CI/CD", "GitHub Actions log in through OIDC roles, push images to ECR, run Terraform plan / apply, deploy ECS services, approve models."),
    ("P-4", "Platform", "Backup / DR / cost", "AWS Backup (RDS and buckets), RDS point-in-time restore, optional cross-region copy, budgets and cost anomaly alerts."),
]

# (layer, AWS service, resource, name (use {e} for dev / stg / prd), quantity per env, flow step, what it does in the v4
#  flow, key configuration, (dev, staging, prod) setting, depends on, scope, owner)
#  + (change vs v4, note) in the last field.
R = []
SAME, CHANGED, NEW = "Same", "Changed", "New"


def add(layer, service, resource, name, qty, flow, what, config, per_env, depends, scope, owner, change=(SAME, "")):
    R.append((layer, service, resource, name, qty, flow, what, config, per_env, depends, scope, owner, change))


L = "01. Account baseline"
add(L, "AWS Organizations", "AWS account per environment", "wbd-mmm-dev / wbd-mmm-stage / wbd-mmm-prod", ALL1, "P-1",
    "Separate WBD-owned account per environment; every resource below is created in each account.", "Member of the WBD organization; budget owner per account",
    s("Dev", "Staging", "Prod"), "-", BASE, PLAT)
add(L, "AWS Organizations", "Service Control Policies", "WBD standard SCPs", ALL1, "P-1",
    "Region lock and guardrails. Must allow us-east-1 (+ us-west-2 for DR) and the services of this list (ECS, Lambda, Step Functions, Glue, SageMaker, Bedrock, API Gateway, Firehose).",
    "Allow-list of the services above", s("same"), "AWS account", BASE, PLAT)
add(L, "IAM Identity Center", "Permission sets", "ReadOnly, Developer, DevOps, Security, BreakGlass", s("5"), "P-1",
    "SSO access for engineers: IAM Identity Center with Okta as the identity source (slide 2 'Okta ... IAM Identity Center'); no IAM users. BreakGlass use raises an alert (rule breakglass-used).",
    "Okta federated to IAM Identity Center (SAML + SCIM); prod: DevOps time-limited elevation",
    s("DevOps + ReadOnly", "DevOps + ReadOnly", "ReadOnly; DevOps on approval"), "Okta groups", BASE, PLAT,
    (CHANGED, "Slide 2 now shows IAM Identity Center under Okta - confirm Okta is the Identity Center identity source"))
add(L, "CloudTrail", "Organization trail", "WBD org trail", ALL1, "P-2",
    "Audit of every API call; management events must reach EventBridge in the account (break-glass alert).", "Multi-region, log file validation", s("same"), "-", BASE, PLAT)
add(L, "CloudTrail", "CloudTrail S3 data events for the MMM data buckets", "WBD org trail selector (or trail mmm-{e}-data-events)", ALL1, "P-2",
    "'CloudTrail - to be enabled across all components': object-level audit (who read / wrote) on landing, lakehouse, training-data, models, uploads, results, approved-worm.",
    "Advanced event selectors on the 7 buckets; delivered to the WBD log archive", s("write events", "read + write", "read + write"), "S3 buckets", OPT, PLAT,
    (NEW, "Environment-level box on both slides; default: WBD adds the selectors to the org trail"))
add(L, "GuardDuty", "GuardDuty detector", "WBD standard", ALL1, "P-1",
    "Threat detection; severity >= 7 findings raise an alert (rule guardduty-high).", "S3 / runtime protection per WBD standard", s("same"), "-", BASE, SEC)
add(L, "Security Hub", "Security Hub", "WBD standard", ALL1, "P-1", "Central security findings (AWS Foundational, CIS).", "-", s("same"), "-", BASE, SEC)
add(L, "AWS Config", "Config recorder + rules", "WBD standard", ALL1, "P-1", "Records resource settings and flags non-compliant ones.", "-", s("same"), "-", BASE, SEC)
add(L, "Inspector", "Amazon Inspector (ECR scanning)", "WBD standard", ALL1, "P-3",
    "Enhanced scanning of the 4 ECR images (api, ui, optimizer, sagemaker-training).", "ECR enhanced scanning on", s("same"), "ECR", BASE, SEC)
add(L, "IAM Access Analyzer", "Access Analyzer", "WBD standard", ALL1, "P-1", "Flags resources shared outside the account (e.g. the Databricks Unity Catalog role - expected).", "-", s("same"), "-", BASE, SEC)
add(L, "S3", "Block Public Access (account level)", "account setting", ALL1, "P-1", "No bucket can be made public.", "All four settings on", s("same"), "-", BASE, PLAT)
add(L, "EC2", "EBS encryption by default", "account setting", ALL1, "P-1", "Every new disk is encrypted.", "On", s("same"), "-", BASE, PLAT)
add(L, "Service Quotas", "Fargate On-Demand vCPU", "account quota", ALL1, "S2-6",
    "One optimizer task per run + api / ui tasks must fit: max_concurrent_runs x optimizer vCPU + services.", "Request before the load test",
    s(">= 40 vCPU", ">= 120 vCPU", ">= 450 vCPU"), "-", QUOTA, PLAT)
add(L, "Service Quotas", "AWS Glue concurrent job runs / DPUs", "account quota", ALL1, "S1-4..S1-7",
    "6 Glue jobs x 3 business units can run at the same time.", "Request before the first full refresh",
    s(">= 20 runs", ">= 20 runs", ">= 20 runs; DPUs for 10 workers x jobs"), "-", QUOTA, PLAT)
add(L, "Service Quotas", "SageMaker training / processing instances", "account quota", ALL1, "S1-8, S1-9, S1-12",
    "ml.m5.2xlarge training and ml.m5.xlarge processing (evaluation, drift) per business unit.", "Request before the first refresh",
    s(">= 3 each", ">= 3 each", ">= 3 each"), "-", QUOTA, PLAT)
add(L, "Macie", "Amazon Macie", "WBD standard", ALL1, "P-1", "Finds sensitive data in S3 (uploads, landing).", "-", s("optional"), "S3 buckets", OPT, SEC)

L = "02. Terraform state"
add(L, "S3", "S3 bucket - Terraform state", "wbd-mmm-{e}-tfstate-use1", ALL1, "P-3",
    "Stores the Terraform state of this environment (only if WBD uses Terraform to create the resources).", "Versioned, SSE-KMS, TLS-only, public access blocked, S3 native lock file",
    s("old versions 90 d", "old versions 90 d", "old versions 365 d"), "KMS key tfstate", OPT, INFRA)
add(L, "KMS", "KMS key - Terraform state", "alias/mmm-{e}-tfstate", ALL1, "P-3", "Encrypts the state bucket.", "Rotation on", s("same"), "-", OPT, INFRA)

L = "03. Encryption (KMS)"
for key, use, flow in (
    ("s3", "S3 buckets (results, approved-worm, exports, models, uploads, glue-assets), Glue catalog + Glue security configuration", "S1-4..S1-10, S2-3..S2-10"),
    ("rds", "RDS PostgreSQL storage, Performance Insights, snapshots", "S1-7, S2-2, S2-8"),
    ("logs", "CloudWatch log groups, Glue logs, Firehose", "P-2"),
    ("secrets", "Secrets Manager secrets, SSM SecureString parameters", "P-1"),
    ("ecr", "ECR repositories", "P-3"),
    ("sqs", "SQS queue and dead-letter queue", "S2-4"),
    ("sagemaker", "SageMaker training / processing volumes and outputs, model packages", "S1-8..S1-10"),
):
    add(L, "KMS", f"KMS key - {key}", "alias/mmm-{e}-" + key, ALL1, flow, f"Encrypts: {use}.",
        "Customer managed, rotation on, key policy = account root + the roles that use it", s("same"), "-", CORE if key != "sagemaker" else DP, INFRA)
add(L, "KMS", "KMS keys - one per business unit (S3)", "alias/mmm-{e}-s3-streaming / -s3-theatrical / -s3-usnetworks", s("3"), "S1-3..S1-7",
    "Business-unit data isolation: objects under <bu>/ in landing, lakehouse and training-data must use the key of that BU (bucket policy).",
    "Rotation on; used by Databricks UC role, export Lambda, Glue, SageMaker", s("same"), "-", DP, INFRA)
add(L, "KMS", "KMS key - genai", "alias/mmm-{e}-genai", ALL1, "S2-9", "Encrypts the LLM gateway logs and the LLM provider secrets.", "Rotation on", s("same"), "-", GENAI, INFRA)
add(L, "KMS", "KMS key - alerts", "alias/mmm-{e}-alerts", ALL1, "P-2", "Encrypts the SNS alert topic (CloudWatch, EventBridge, Budgets may use it).", "Rotation on", s("same"), "-", CORE, INFRA)
add(L, "KMS", "KMS key - backup vault", "alias/mmm-{e}-backup", ALL1, "P-4", "Encrypts the AWS Backup vault.", "Rotation on", s("same"), "-", CORE, INFRA)
add(L, "KMS", "KMS key - backup DR vault (us-west-2)", "alias/mmm-{e}-backup-dr", ALL1, "P-4", "Encrypts the DR copy vault in the DR region.", "Rotation on; DR region", s("-", "-", "if approved"), "-", OPT, INFRA)

L = "04. IAM foundation and CI/CD access"
add(L, "IAM", "IAM permission boundary", "mmm-{e}-permission-boundary", ALL1, "P-1",
    "Attached to every role in this list; caps what a role can do even if its policy is too broad.", "Managed policy", s("same"), "-", CORE, INFRA)
add(L, "IAM", "IAM OIDC identity provider - GitHub", "token.actions.githubusercontent.com", ALL1, "P-3",
    "Lets GitHub Actions log in to AWS without stored keys.", "Audience sts.amazonaws.com", s("same"), "-", CORE, INFRA)
for role, what in (
    ("gha-plan", "Terraform plan on pull requests (read-only)"),
    ("gha-apply", "Terraform apply after approval (only if WBD lets the pipeline apply; otherwise WBD Infra applies)"),
    ("gha-ecr-push", "Push images to the 4 ECR repositories (api, ui, optimizer, sagemaker-training)"),
    ("gha-deploy", "Deploy: run the migrate task, register task definitions (api, ui, migrate, optimizer), update the ECS services, write SSM release pointers, upload Glue scripts, publish the Lambda alias"),
    ("gha-model-eval", "Model governance: read model packages and evaluation reports"),
    ("gha-model-approve", "Model governance: approve / reject model packages and publish approved curves (prod: WBD approver)"),
):
    add(L, "IAM", f"IAM role - GitHub {role}", "mmm-{e}-" + role, ALL1, "P-3", what + ".",
        "Trust: GitHub OIDC, repo + branch / environment; permission boundary", s("same"), "OIDC provider", CORE, INFRA)
add(L, "Budgets", "AWS Budget - monthly", "mmm-{e}-monthly", ALL1, "P-4", "Email at 50 / 80 / 100 % of the monthly budget.", "Cost type unblended",
    s("3,000 USD", "6,000 USD", "15,000 USD"), "SNS / email", CORE, INFRA)
add(L, "Cost Explorer", "Cost anomaly monitor + subscription", "mmm-{e}-services / mmm-{e}-anomalies", s("2"), "P-4",
    "Daily alert on unexpected spend per service (Glue DPU-hours, Fargate, SageMaker).", "Daily summary", s("same"), "-", CORE, INFRA)

L = "05. Networking"
add(L, "VPC", "VPC", "mmm-{e}-vpc", ALL1, "P-1", "Private network for all workloads of the environment.", "DNS hostnames + support on",
    s("10.40.0.0/19", "10.40.32.0/19", "10.40.64.0/19"), "WBD IPAM / CIDR", CORE, INFRA)
add(L, "VPC", "Subnets - public", "mmm-{e}-public-<az>", s("2", "3", "3"), "S2-1", "Public ALB and NAT gateways.", "1 per AZ", s("2 AZ", "3 AZ", "3 AZ"), "VPC", CORE, INFRA)
add(L, "VPC", "Subnets - private app", "mmm-{e}-app-<az>", s("2", "3", "3"), "S1-2..S1-12, S2-2..S2-9",
    "ECS tasks (ui, api, optimizer, migrate), Lambdas (publisher, dispatcher, Databricks export, LLM proxy), Glue job ENIs, SageMaker job ENIs.", "1 per AZ; no public IPs", s("2 AZ", "3 AZ", "3 AZ"), "VPC", CORE, INFRA)
add(L, "VPC", "Subnets - private data", "mmm-{e}-data-<az>", s("2", "3", "3"), "S2-2", "RDS PostgreSQL and RDS Proxy; no internet route.", "1 per AZ", s("2 AZ", "3 AZ", "3 AZ"), "VPC", CORE, INFRA)
add(L, "VPC", "Subnets - private endpoint", "mmm-{e}-endpoint-<az>", s("2", "3", "3"), "P-1", "Interface VPC endpoints (and the Route 53 resolver endpoint if used).", "1 per AZ", s("2 AZ", "3 AZ", "3 AZ"), "VPC", CORE, INFRA)
add(L, "VPC", "Internet gateway", "mmm-{e}-igw", ALL1, "S2-1", "Internet access for the public subnets (ALB in, NAT out).", "-", s("same"), "VPC", CORE, INFRA)
add(L, "VPC", "NAT gateways + Elastic IPs", "mmm-{e}-nat-<az>", s("1", "3", "3"), "S1-2, S2-9",
    "Outbound only: Databricks workspace API (export Lambda), Okta token calls, LLM providers. NAT IPs go on the Databricks IP access list.", "Dev single NAT; staging / prod 1 per AZ",
    s("1 NAT", "3 NAT", "3 NAT"), "Public subnets, IGW", CORE, INFRA)
add(L, "VPC", "Route tables + associations", "mmm-{e}-public / -app-<az> / -data / -endpoint", s("5", "6", "6"), "P-1",
    "public -> IGW; app -> NAT (+ WBD network via Transit Gateway if used); data and endpoint -> local only.", "App route table per AZ", s("same"), "Subnets, NAT", CORE, INFRA)
add(L, "VPC", "VPC gateway endpoints - S3, DynamoDB", "com.amazonaws.us-east-1.s3 / .dynamodb", s("2"), "S1-3..S1-12, S2-3..S2-10",
    "Private, free access to S3 (all buckets, ECR layers) from tasks, Lambdas, Glue and SageMaker.", "Attached to app, data and endpoint route tables", s("same"), "Route tables", CORE, INFRA)
add(L, "VPC", "VPC interface endpoints - core", "ecr.api, ecr.dkr, sts, kms, logs, monitoring, secretsmanager, ssm, ssmmessages, sqs, states, xray, sagemaker.api",
    s("13"), "P-1", "Private access to AWS APIs from the private subnets: image pulls, secrets, logs, metrics, SQS, Step Functions, SageMaker registry (optimizer), ECS Exec.",
    "Private DNS on; endpoint subnets; SG endpoints", s("same"), "Endpoint subnets, SG endpoints", CORE, INFRA)
add(L, "VPC", "VPC interface endpoint - glue", "com.amazonaws.us-east-1.glue", ALL1, "S1-4..S1-7", "Glue job ENIs reach the Glue API privately.", "Private DNS on", s("same"), "SG endpoints", DP, INFRA)
add(L, "VPC", "VPC interface endpoints - execute-api, bedrock-runtime", "com.amazonaws.us-east-1.execute-api / .bedrock-runtime", s("2"), "S2-9",
    "Private API Gateway (LLM gateway) and Bedrock ApplyGuardrail calls.", "Private DNS on", s("same"), "SG endpoints", GENAI, INFRA)
add(L, "VPC", "Default security group (locked down)", "default", ALL1, "P-1", "No rules, so nothing uses it by accident.", "No ingress / egress", s("same"), "VPC", CORE, INFRA)
add(L, "VPC", "VPC flow logs + log group + IAM role", "/aws/vpc/mmm-{e}/flow-logs ; role mmm-{e}-vpc-flow-logs", s("3"), "P-2", "Network traffic records for security investigations.", "All traffic; KMS logs",
    s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "EC2", "Transit Gateway attachment", "mmm-{e}-tgw", ALL1, "P-1", "Connects the VPC to the WBD network (VDI, Splunk, on-prem) if required.", "Routes e.g. 10.0.0.0/8 from the app subnets",
    s("if required"), "WBD Transit Gateway", OPT, INFRA)
add(L, "Route 53 Resolver", "Outbound resolver endpoint + forwarding rule + SG", "mmm-{e}-outbound ; mmm-{e}-fwd-wbd-internal ; mmm-{e}-resolver-sg", s("3"), "P-1",
    "Resolves WBD internal names (wbd.internal) through WBD DNS servers.", "DNS 53 tcp/udp to WBD resolvers", s("if required"), "Transit Gateway", OPT, INFRA)
add(L, "VPC", "Databricks PrivateLink endpoint + private hosted zone + record", "Databricks workspace endpoint ; zone <workspace>.cloud.databricks.com", s("3"), "S1-2",
    "Export Lambda reaches the Databricks workspace API privately instead of through NAT.", "Service name from Databricks", s("if required"), "Databricks account", OPT, INFRA)

L = "06. Security groups"
for sg, what, rules, flow, scope in (
    ("alb", "Public ALB", "In 443 (and 80 -> redirect) from 0.0.0.0/0 or WBD ranges; out 8080 to ui + api SGs, 443 to Okta", "S2-1", CORE),
    ("ui", "ECS ui tasks", "In 8080 from ALB SG; out 443 to endpoints and S3 prefix list", "S2-2", CORE),
    ("api", "ECS api tasks", "In 8080 from ALB SG; out 443 to endpoints, S3 and the ALB token-signing keys (+ data-clients SG for the DB)", "S2-2", CORE),
    ("tasks", "ECS one-off tasks (migrate, platform-check)", "No inbound; out 443 to endpoints, S3, package indexes", "P-3", CORE),
    ("optimizer", "ECS optimizer tasks", "No inbound; out 443 to endpoints and S3 prefix list only (no database)", "S2-6", CORE),
    ("lambda", "Lambdas results publisher + dispatcher", "No inbound; out 443 to endpoints and S3 (+ data-clients SG for the DB)", "S2-5, S2-8, S1-11", CORE),
    ("data-clients", "Everything that talks to the database (api, migrate, results/data publisher)", "Out 5432 to RDS Proxy SG; out 443 to endpoints / S3", "S1-11, S2-2, S2-8", CORE),
    ("rds-proxy", "RDS Proxy", "In 5432 from data-clients SG; out 5432 to RDS SG", "S2-2", CORE),
    ("rds", "RDS PostgreSQL", "In 5432 from RDS Proxy SG only", "S2-2", CORE),
    ("endpoints", "Interface VPC endpoints", "In 443 from the VPC CIDR", "P-1", CORE),
    ("sagemaker", "SageMaker training / processing jobs", "Self-referencing (distributed training); out 443 to endpoints and S3", "S1-8, S1-9, S1-12", DP),
    ("glue", "Glue job ENIs", "Self-referencing all traffic (Spark driver <-> executors); out 443 to endpoints and S3", "S1-4..S1-7", DP),
    ("databricks-export", "Databricks export Lambda", "No inbound; out 443 to the Databricks workspace (NAT or PrivateLink) and endpoints", "S1-2", DP),
    ("genai", "LLM proxy Lambda", "No inbound; out 443 to the approved LLM providers and endpoints", "S2-9", GENAI),
):
    chg = (CHANGED, "Glue no longer attaches it (Gold -> RDS goes through the publisher)") if sg == "data-clients" else \
          (CHANGED, "Without the data-clients SG - Glue has no database path") if sg == "glue" else (SAME, "")
    add(L, "VPC", f"Security group - {sg}", "mmm-{e}-" + sg + "-sg", ALL1, flow, what + ".", rules, s("same"), "VPC", scope, INFRA, chg)

L = "07. Container registry (ECR)"
for repo, what, flow, scope in (
    ("mmm/api", "API image (FastAPI + LangGraph), also used by the migrate and platform-check tasks", "S2-2", CORE),
    ("mmm/ui", "UI image (React + TypeScript, nginx, QA dashboard)", "S2-2", CORE),
    ("mmm/optimizer", "ECS inference & optimization image (Model Summarizer, Optimizer, Simulation)", "S2-6", CORE),
    ("mmm/sagemaker-training", "SageMaker training / evaluation / drift image", "S1-8, S1-9, S1-12", DP),
):
    add(L, "ECR", f"ECR repository - {repo}", repo, ALL1, flow, what + ".",
        "Tag immutability, scan on push, KMS ecr, lifecycle: keep last 20 tagged, delete untagged after 7 d", s("same"), "KMS ecr", scope, INFRA)
add(L, "ECR", "ECR registry scanning configuration", "registry setting", ALL1, "P-3", "Enhanced (Inspector) continuous scanning of every repository.", "Enhanced, continuous", s("same"), "Inspector", CORE, INFRA)

L = "08. Secrets and parameters"
for name, what, flow, scope, who in (
    ("api/db", "DB user of the API (mmm_app) - used through RDS Proxy", "S2-2", CORE, "Value set by the DB bootstrap"),
    ("rds/migrate", "DB user mmm_migrator of the migrate task (schema owner)", "P-3", CORE, "Value set by the DB bootstrap"),
    ("rds/proxy", "DB user list for RDS Proxy authentication", "S2-2", CORE, "Value set by the DB bootstrap"),
    ("okta/alb-client", "Okta OIDC client secret used by the ALB sign-in", "S2-1", CORE, "Value entered by WBD Identity / DevOps"),
    ("databricks/export-sp", "Databricks service principal OAuth client id + secret for the export Lambda", "S1-2", DP, "Value entered by WBD Databricks admins"),
    ("splunk/hec", "Splunk HEC token for Firehose", "P-2", OPT, "Value entered by WBD Splunk team"),
    ("thirdparty/adstra", "Third-party vendor API key (only if still needed)", "S1-3", OPT, "Value entered by WBD"),
    ("thirdparty/inscape", "Third-party vendor API key (only if still needed)", "S1-3", OPT, "Value entered by WBD"),
    ("llm/openai", "OpenAI API key for the LLM proxy", "S2-9", GENAI, "Value entered by WBD"),
    ("llm/anthropic", "Anthropic API key for the LLM proxy", "S2-9", GENAI, "Value entered by WBD"),
    ("llm/google", "Google API key for the LLM proxy", "S2-9", GENAI, "Value entered by WBD"),
):
    add(L, "Secrets Manager", f"Secret - {name}", "mmm/{e}/" + name, ALL1, flow, what + ".", f"KMS secrets; {who} (never by email)",
        s("recovery 7 d", "recovery 7 d", "recovery 30 d"), "KMS secrets", scope, INFRA)
add(L, "RDS", "RDS master password (RDS-managed secret)", "rds!db-... (created by RDS)", ALL1, "S2-2", "Admin password of the database, created and rotated by RDS.", "manage_master_user_password, KMS secrets", s("same"), "RDS instance", CORE, INFRA)
for name, what, flow, scope, val in (
    ("ecs/optimizer_task_definition", "ARN of the optimizer task definition revision every run uses (release / rollback pointer)", "S2-6", CORE, "written by the deploy pipeline"),
    ("optimization/max_concurrent_runs", "How many optimization runs may run at the same time (read by the dispatcher)", "S2-5", CORE, "5 / 20 / 50"),
    ("okta/issuer", "Okta issuer URL", "S2-1", CORE, "https://wbd.okta.com/oauth2/default (# add actual value)"),
    ("images/sagemaker-training", "Training image URI (digest) used by the refresh", "S1-8", DP, "written by the deploy pipeline"),
    ("databricks/host", "Databricks workspace URL", "S1-2", DP, "# add actual value"),
    ("databricks/export_job_ids", "JSON map business unit -> Databricks export job id", "S1-2", DP, '{"streaming": ..., ...} # add actual value'),
    ("genai_enabled", "GenAI on / off switch without redeploy", "S2-9", GENAI, "false until approved"),
    ("genai/token_quota/<bu>", "Daily token quota per business unit (3 parameters)", "S2-9", GENAI, "1,000,000 tokens/day"),
):
    add(L, "SSM Parameter Store", f"Parameter - {name}", "/mmm/{e}/" + name, s("3") if "<bu>" in name else ALL1, flow, what + ".",
        "String (SecureString with KMS secrets where noted)", s(val), "-", scope, INFRA)

L = "09. Storage (S3)"
BUCKET_STD = "Versioning, SSE-KMS, TLS-only + deny unencrypted PUT policy, public access blocked, BucketOwnerEnforced, access logs to the logs bucket, old versions 90 d"
add(L, "S3", "S3 bucket - logs", "wbd-mmm-{e}-logs-use1", ALL1, "P-2", "ALB access logs and S3 server access logs of all other buckets.",
    "SSE-S3 (log delivery), versioning, public access blocked, lifecycle", s("expire 90 d", "expire 90 d", "expire 365 d"), "-", CORE, INFRA)
add(L, "S3", "S3 bucket - landing (raw data from Databricks)", "wbd-mmm-{e}-landing-use1", ALL1, "S1-3",
    "Raw data exported from the Databricks source catalog: raw/databricks/<bu>/<date>/ (Parquet + _manifest.json), 3+ years of history.",
    BUCKET_STD + "; per-BU KMS key enforced under <bu>/; EventBridge notifications on; Glacier after 365 d; write by Databricks UC role only on raw/databricks/*",
    s("same"), "KMS s3 + BU keys, logs bucket", DP, INFRA)
add(L, "S3", "S3 bucket - lakehouse (Delta Lake)", "wbd-mmm-{e}-lakehouse-use1", ALL1, "S1-4..S1-7, S1-11, S1-12",
    "Bronze / Silver / Gold Delta tables written by Glue; rds-export/<bu>/<refresh_id>/ Gold reference data read by the results/data publisher; monitoring/<bu>/<date>/ features for the drift check.",
    BUCKET_STD + "; per-BU KMS; monitoring/ expires after 90 d, rds-export/ after 30 d",
    s("same"), "KMS BU keys", DP, INFRA, (CHANGED, "New prefix rds-export/ (Gold -> RDS now goes through the publisher)"))
add(L, "S3", "S3 bucket - training-data", "wbd-mmm-{e}-training-data-use1", ALL1, "S1-7, S1-8",
    "Immutable Parquet snapshot + metadata per refresh (training-data/<bu>/<refresh_id>/) so every model version can be reproduced.",
    BUCKET_STD + "; Object Lock; per-BU KMS; Glacier after 180 d",
    s("GOVERNANCE 365 d", "GOVERNANCE 365 d", "COMPLIANCE 730 d"), "KMS BU keys", DP, INFRA)
add(L, "S3", "S3 bucket - glue-assets", "wbd-mmm-{e}-glue-assets-use1", ALL1, "S1-4..S1-7",
    "Glue job scripts (scripts/<job>.py, uploaded by the pipeline) and Spark temp files (temp/).", BUCKET_STD + "; temp/ expires after 7 d", s("same"), "KMS s3", DP, INFRA)
add(L, "S3", "S3 bucket - models", "wbd-mmm-{e}-models-use1", ALL1, "S1-8..S1-10, S2-6",
    "Model artifacts, evaluation reports (evaluation/), predictions / lift, approved response curves (curves/<bu>/), drift baselines; read by the optimizer.",
    BUCKET_STD, s("same"), "KMS s3", CORE, INFRA)
add(L, "S3", "S3 bucket - uploads (user input files)", "wbd-mmm-{e}-uploads-use1", ALL1, "S2-3, S2-6",
    "Inventory and future-title files uploaded by planners: <bu>/runs/<run_id>/input/ through presigned PUT from the browser.",
    BUCKET_STD + "; CORS = app URL only (PUT, GET)", s("expire 90 d"), "KMS s3, app domain", CORE, INFRA)
add(L, "S3", "S3 bucket - results (run outputs)", "wbd-mmm-{e}-results-use1", ALL1, "S2-7, S2-8",
    "Full run evidence of every optimization (runs/<run_id>/output, solver logs) written by the optimizer task; read by the publisher.", BUCKET_STD, s("same"), "KMS s3", CORE, INFRA)
add(L, "S3", "S3 bucket - approved-worm (Object Lock)", "wbd-mmm-{e}-approved-worm-use1", ALL1, "S2-10",
    "Approved scenarios that can never be changed (audit).", BUCKET_STD + "; Object Lock (must be enabled when the bucket is created)",
    s("GOVERNANCE 2555 d", "GOVERNANCE 2555 d", "COMPLIANCE 2555 d"), "KMS s3", CORE, INFRA)
add(L, "S3", "S3 bucket - exports", "wbd-mmm-{e}-exports-use1", ALL1, "S2-10", "Excel exports downloaded by planners.", BUCKET_STD, s("expire 30 d"), "KMS s3", CORE, INFRA)
add(L, "GuardDuty", "Malware Protection for S3 (uploads bucket)", "uploads bucket", ALL1, "S2-3", "Scans uploaded files before the optimizer reads them.", "Tag-based access", s("if required"), "uploads bucket", OPT, SEC)

L = "10. Database (RDS PostgreSQL)"
add(L, "RDS", "DB subnet group", "mmm-{e}-postgres-subnets", ALL1, "S2-2", "Places the database in the private data subnets.", "Data subnets", s("same"), "Data subnets", CORE, INFRA)
add(L, "RDS", "DB parameter group", "mmm-{e}-postgres-params", ALL1, "S2-2", "rds.force_ssl = 1, pgaudit, slow-query logging.", "Family postgres16", s("same"), "-", CORE, INFRA)
add(L, "RDS", "RDS for PostgreSQL instance", "mmm-{e}-postgres", ALL1, "S1-11, S2-2, S2-8",
    "System of record: plans, runs, allocations, audit, Gold reference tables and model predictions / lift / evaluation (both written by the results/data publisher). Row-level security per BU.",
    "PostgreSQL 16.6, gp3, KMS rds, Performance Insights, Enhanced Monitoring, IAM auth, logs postgresql + upgrade to CloudWatch, deletion protection (prod)",
    s("db.t4g.medium, single-AZ, 50 GB (max 200), backup 7 d", "db.r6g.large, Multi-AZ, 100 GB (max 500), backup 14 d", "db.r6g.xlarge, Multi-AZ, 200 GB (max 1000), backup 35 d"),
    "Subnet group, SG rds, KMS rds", CORE, INFRA)
add(L, "IAM", "IAM role - RDS Enhanced Monitoring", "mmm-{e}-postgres-monitoring", ALL1, "P-2", "OS metrics of the DB instance.", "AmazonRDSEnhancedMonitoringRole", s("same"), "-", CORE, INFRA)
add(L, "RDS", "RDS Proxy + target group + target", "mmm-{e}-postgres-proxy", s("3"), "S1-11, S2-2, S2-8",
    "Connection pooling for the API tasks and the results/data publisher Lambda; TLS required; IAM auth.", "Secrets api/db, rds/migrate, rds/proxy; data subnets; SG rds-proxy", s("same"), "RDS, secrets", CORE, INFRA,
    (CHANGED, "rds/etl removed (no Glue client)"))
add(L, "IAM", "IAM role - RDS Proxy", "mmm-{e}-postgres-proxy", ALL1, "S2-2", "Lets RDS Proxy read the DB user secrets.", "secretsmanager:GetSecretValue + kms:Decrypt", s("same"), "Secrets", CORE, INFRA)
add(L, "CloudWatch Logs", "Log groups - RDS", "/aws/rds/instance/mmm-{e}-postgres/postgresql ; /upgrade", s("2"), "P-2", "Database and upgrade logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "PostgreSQL", "DB users and schema (inside the database)", "mmm_app (API + results/data publisher), mmm_migrator", s("2"), "S1-11, S2-2", "Least-privilege users; tables and row-level security from the backend migrations.",
    "Created by the DB bootstrap + migrate task", s("same"), "RDS", CORE, APPT, (CHANGED, "mmm_etl removed; the publisher (mmm_app) also writes the Gold reference tables"))

L = "11. ECS on Fargate (UI and API)"
add(L, "ECS", "ECS cluster", "mmm-{e}-ecs", ALL1, "S2-2, S2-6", "Runs the ui and api services, the optimizer tasks and one-off tasks.", "Fargate + Fargate Spot capacity providers, Container Insights (enhanced), ECS Exec logging",
    s("same"), "-", CORE, INFRA)
add(L, "Cloud Map", "Service Connect namespace", "mmm-{e}.internal", ALL1, "S2-2", "Service-to-service names inside the cluster.", "HTTP namespace", s("same"), "ECS cluster", CORE, INFRA)
add(L, "CloudWatch Logs", "Log group - ECS Exec audit", "/ecs/mmm-{e}/exec-audit", ALL1, "P-2", "Records every ECS Exec session (break-glass debugging).", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "IAM", "IAM role - ECS task execution", "mmm-{e}-ecs-task-exec", ALL1, "S2-2, S2-6", "Pulls images from ECR, writes logs, injects the listed secrets into containers.", "Permission boundary", s("same"), "ECR, secrets", CORE, INFRA)
for name, what, sizing, flow in (
    ("api", "FastAPI + LangGraph tools: plans, what-if, presigned uploads, queues runs; health /api/health", s("1 vCPU / 2 GB", "1 vCPU / 2 GB", "1 vCPU / 2 GB"), "S2-2..S2-4, S2-9"),
    ("ui", "React + TypeScript web app with the QA dashboard (nginx, non-root); health /healthz", s("0.25 vCPU / 0.5 GB"), "S2-2"),
    ("migrate", "One-off task that runs the DB migrations before every deploy", s("0.25 vCPU / 0.5 GB"), "P-3"),
    ("platform-check", "One-off task that checks the release pointers and connectivity after a deploy", s("0.25 vCPU / 0.5 GB"), "P-3"),
):
    add(L, "ECS", f"ECS task definition - {name}", "mmm-{e}-" + name, ALL1, flow, what + ".", "Fargate, Linux ARM64/X86 per image, read-only root FS, non-root, awslogs", sizing,
        "ECR image, exec role, task role", CORE, INFRA_PIPE)
    add(L, "IAM", f"IAM role - task {name}", "mmm-{e}-task-" + name, ALL1, flow,
        {"api": "API permissions: rds-db:connect via Proxy, presign read / write on uploads, read results / models, SendMessage to SQS, put metrics (+ execute-api with GenAI)",
         "ui": "UI permissions: none beyond logs (static web)",
         "migrate": "Migrate permissions: rds-db:connect as mmm_migrator",
         "platform-check": "Read SSM release pointers, describe ECS / Step Functions"}[name] + ".", "Permission boundary", s("same"), "-", CORE, INFRA)
    add(L, "CloudWatch Logs", f"Log group - {name}", "/ecs/mmm-{e}/" + name, ALL1, "P-2", f"Container logs of {name}.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "ECS", "ECS service - api", "mmm-{e}-api", ALL1, "S2-2", "API tasks behind the ALB target group api-tg.", "Private app subnets, SG api + data-clients, circuit breaker with rollback, ECS Exec",
    s("1-2 tasks", "2-4 tasks", "3-10 tasks"), "Task definition, ALB", CORE, INFRA)
add(L, "ECS", "ECS service - ui", "mmm-{e}-ui", ALL1, "S2-2", "UI tasks behind the ALB target group ui-tg.", "Private app subnets, SG ui, circuit breaker with rollback",
    s("1-2 tasks", "2-3 tasks", "2-6 tasks"), "Task definition, ALB", CORE, INFRA)
add(L, "Application Auto Scaling", "Scaling targets + CPU policies - api, ui", "mmm-{e}-api-cpu ; mmm-{e}-ui-cpu", s("4"), "S2-2", "Adds tasks in planning seasons (50-150 planners).", "Target tracking CPU 60 %",
    s("same"), "ECS services", CORE, INFRA)

L = "12. Front door and sign-in"
add(L, "ACM", "ACM certificate (app domain)", "mmm-dev / mmm-stg / mmm .<wbd domain>", ALL1, "S2-1", "TLS certificate of the app name on the ALB.", "DNS validated, us-east-1", s("mmm-dev.<domain>", "mmm-stg.<domain>", "mmm.<domain>"), "WBD DNS", CORE, DNS)
add(L, "Elastic Load Balancing", "Application Load Balancer (public entry)", "mmm-{e}-alb", ALL1, "S2-1",
    "Single HTTPS entry for planners: /api/* -> API, /* -> UI; signs users in with Okta first.", "Internet-facing, public subnets, SG alb, access logs to logs bucket, drop invalid headers, deletion protection (prod)",
    s("same"), "Public subnets, ACM, logs bucket", CORE, INFRA)
add(L, "Elastic Load Balancing", "Listeners - HTTPS 443 + HTTP 80 (redirect)", "mmm-{e}-alb :443 / :80", s("2"), "S2-1",
    "443: authenticate-oidc (Okta) then forward; 80: redirect to 443.", "TLS policy ELBSecurityPolicy-TLS13-1-2-2021-06", s("same"), "ALB, ACM, Okta app", CORE, INFRA)
add(L, "Elastic Load Balancing", "Listener rules - /api/*, /api/health", "mmm-{e}-alb rules", s("2"), "S2-1", "API path to api-tg (401 when not signed in); health path without sign-in.", "-", s("same"), "Listener", CORE, INFRA)
add(L, "Elastic Load Balancing", "Target groups - api, ui", "mmm-{e}-api-tg ; mmm-{e}-ui-tg", s("2"), "S2-2", "IP targets for the ECS services.", "Port 8080, health /api/health and /healthz, deregistration 30 s",
    s("same"), "VPC", CORE, INFRA)
add(L, "WAF", "WAF web ACL (regional) + association", "mmm-{e}-alb", s("2"), "S2-1", "Blocks common attacks and floods before the ALB.",
    "AWS managed rules (common, known bad inputs, IP reputation, SQLi), rate limit per IP", s("2000 req / 5 min"), "ALB", CORE, INFRA)
add(L, "WAF", "WAF logging + log group", "aws-waf-logs-mmm-{e}", s("2"), "P-2", "WAF request logs (to Splunk when shipping is on).", "KMS logs", s("30 d", "90 d", "365 d"), "WAF", CORE, INFRA)
add(L, "Route 53", "DNS record for the app", "mmm-dev / mmm-stg / mmm .<wbd domain>", ALL1, "S2-1", "App name -> ALB.", "Alias (our zone) or CNAME in WBD DNS", s("same"), "ALB", CORE, DNS)
add(L, "Okta", "Okta OIDC web app per environment", "WBD MMM {e}", ALL1, "S2-1",
    "Authentication and RBAC: groups claim mmm-bu-* / mmm-role-* in the ID token; redirect https://<app>/oauth2/idpresponse.", "MFA per WBD policy; session 12 h", s("same"), "App domain", CORE, IDN)

L = "13. Optimization engine (slide 2)"
add(L, "SQS", "SQS queue - optimization requests", "mmm-{e}-optimization-requests", ALL1, "S2-4", "One message per optimization / forecast run sent by the API; absorbs bursts in planning seasons.",
    "KMS sqs, visibility 360 s, retention 4 d, redrive to DLQ after 10 receives, TLS-only policy", s("same"), "KMS sqs", CORE, INFRA)
add(L, "SQS", "SQS dead-letter queue", "mmm-{e}-optimization-requests-dlq", ALL1, "S2-4", "Run requests that failed 10 times; alarm when not empty; redrive runbook.", "KMS sqs, retention 14 d, redrive-allow policy", s("same"), "KMS sqs", CORE, INFRA)
add(L, "Lambda", "Lambda - run dispatcher", "mmm-{e}-run-dispatcher", ALL1, "S2-5", "Reads the queue and starts optimization executions while RUNNING < max_concurrent_runs.",
    "Python 3.12, 256 MB, 60 s, reserved concurrency 2, VPC (app subnets, SG lambda), X-Ray", s("same"), "SQS, Step Functions, SSM", CORE, INFRA_PIPE)
add(L, "Lambda", "Event source mapping SQS -> dispatcher", "-", ALL1, "S2-5", "Delivers queue messages to the dispatcher.", "Batch 10, maximum concurrency 2, partial batch failures", s("same"), "SQS, Lambda", CORE, INFRA)
add(L, "IAM", "IAM role - dispatcher", "mmm-{e}-run-dispatcher-lambda", ALL1, "S2-5", "Consume SQS, StartExecution / ListExecutions, read SSM max_concurrent_runs, put metrics.", "Permission boundary", s("same"), "-", CORE, INFRA)
add(L, "CloudWatch Logs", "Log group - dispatcher", "/aws/lambda/mmm-{e}-run-dispatcher", ALL1, "P-2", "Dispatcher logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "Step Functions", "State machine - optimization", "mmm-{e}-optimization", ALL1, "S2-6, S2-8",
    "ApplyDefaults -> read optimizer task pointer -> RunOptimizer (ecs:runTask.sync, Fargate, private subnets, no public IP) -> invoke results publisher; retries, timeouts.",
    "Standard, logging ALL to CloudWatch, X-Ray", s("same"), "ECS, Lambda publisher, SSM", CORE, INFRA)
add(L, "IAM", "IAM role - optimization state machine", "mmm-{e}-optimization-sfn", ALL1, "S2-6", "ecs:RunTask / StopTask / DescribeTasks, iam:PassRole (optimizer roles), events rule for .sync, invoke publisher, logs.",
    "Permission boundary", s("same"), "-", CORE, INFRA)
add(L, "CloudWatch Logs", "Log group - optimization state machine", "/aws/states/mmm-{e}-optimization", ALL1, "P-2", "Execution history logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "ECS", "ECS task definition - optimizer (inference & optimization)", "mmm-{e}-optimizer", ALL1, "S2-6",
    "One Fargate task per run: Model Summarizer -> Optimizer -> Simulation; reads uploads, approved curves, Model Registry; writes results.",
    "Read-only root FS, non-root, no ECS Exec, max run time 3600 s, ephemeral storage 50 GiB",
    s("4 vCPU / 16 GB", "4 vCPU / 16 GB", "8 vCPU / 32 GB"), "ECR mmm/optimizer, exec role, task role", CORE, INFRA_PIPE)
add(L, "IAM", "IAM role - task optimizer", "mmm-{e}-task-optimizer", ALL1, "S2-6", "Read uploads + models/curves + Model Registry, write results/runs/*, put metrics; no database access.",
    "Permission boundary", s("same"), "-", CORE, INFRA)
add(L, "CloudWatch Logs", "Log group - optimizer", "/ecs/mmm-{e}/optimizer", ALL1, "P-2", "Optimizer task logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "ECS", "ECS optimizer task (one per run)", "started by mmm-{e}-optimization", s("up to 5", "up to 20", "up to 50"), "S2-6", "The running inference & optimization container of one run.",
    "Fargate in the app subnets, SG optimizer", s("max 5 at a time", "max 20 at a time", "max 50 at a time"), "Fargate vCPU quota", RUN, DS)
add(L, "Lambda", "Lambda - results/data publisher (+ alias live)", "mmm-{e}-results-publisher", s("2"), "S1-11, S2-8",
    "'Results/data publisher': writes plans, runs and allocations (optimization), the Glue Gold reference data (refresh, event reference_data) and model predictions, lift and evaluation (refresh, event model_results) from S3 to RDS PostgreSQL.",
    "Python 3.12, 512 MB, 120 s (reference data in batches; 900 s if the tables are large), reserved concurrency 10, VPC (SG lambda + data-clients), X-Ray",
    s("same"), "RDS Proxy, results / models / lakehouse bucket", CORE, INFRA_PIPE,
    (CHANGED, "New event reference_data: loads lakehouse/rds-export/<bu>/<refresh_id>/ into RDS (was the Glue export-rds JDBC write)"))
add(L, "IAM", "IAM role - results/data publisher", "mmm-{e}-results-publisher-lambda", ALL1, "S1-11, S2-8",
    "rds-db:connect via Proxy as mmm_app, read results/runs/*, models/evaluation/* and lakehouse/rds-export/* (+ BU keys), logs.", "Permission boundary", s("same"), "-", CORE, INFRA,
    (CHANGED, "+ read lakehouse/rds-export/* and the per-BU keys"))
add(L, "CloudWatch Logs", "Log group - results publisher", "/aws/lambda/mmm-{e}-results-publisher", ALL1, "P-2", "Publisher logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)

L = "14. Databricks export (slide 1)"
add(L, "IAM", "IAM role - Databricks Unity Catalog (write-only)", "mmm-{e}-databricks-uc", ALL1, "S1-3",
    "Storage credential for the Databricks export job: write only to landing raw/databricks/* with the BU keys.", "Trust: Databricks UC master role + external id", s("same"), "landing bucket, BU keys", DP, INFRA)
add(L, "Lambda", "Lambda - Export Trigger (Databricks API connector)", "mmm-{e}-databricks-export", ALL1, "S1-2, S1-3",
    "'Lambda Functions - Export Trigger' on slide 1: start: OAuth M2M token -> Jobs API run-now (target URI per BU); status: runs/get; writes _manifest.json.",
    "Python 3.12, 256 MB, 60 s, VPC (SG databricks-export), egress via NAT or PrivateLink, X-Ray", s("same"), "Secret databricks/export-sp, SSM job ids", DP, INFRA_PIPE,
    (SAME, "Slide 1 now labels it 'Export Trigger' - confirms the separate export Lambda built in v4"))
add(L, "IAM", "IAM role - Databricks export Lambda", "mmm-{e}-databricks-export-lambda", ALL1, "S1-2", "Read databricks/export-sp + SSM databricks/*, put _manifest.json under landing raw/databricks/, BU keys.", "Permission boundary", s("same"), "-", DP, INFRA)
add(L, "CloudWatch Logs", "Log group - Databricks export", "/aws/lambda/mmm-{e}-databricks-export", ALL1, "P-2", "Export Lambda logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "Databricks", "Databricks export job per business unit", "WBD workspace", s("3"), "S1-2, S1-3", "Exports the source tables as Parquet to the output URI it is given (params business_unit, output_uri, purpose, request_id).",
    "Job id per BU -> SSM databricks/export_job_ids", s("same"), "UC external location", DP, DBX)
add(L, "Databricks", "Service principal (export) + Unity Catalog storage credential + external location", "WBD workspace", s("3"), "S1-2, S1-3",
    "Service principal with 'Can manage run' on the export jobs; external location on s3://landing/raw/databricks/ using role mmm-{e}-databricks-uc.", "Workspace IP access list allows our NAT IPs (or PrivateLink)",
    s("same"), "IAM role databricks-uc", DP, DBX)

L = "15. AWS Glue lakehouse (slide 1)"
add(L, "Glue", "Glue Data Catalog databases - bronze, silver, gold", "mmm_{e}_bronze / mmm_{e}_silver / mmm_{e}_gold", s("3"), "S1-4..S1-6, S1-13",
    "Catalog of the Delta tables in the lakehouse bucket; table properties carry the lineage of each refresh (mmm_refresh_id, mmm_business_unit, mmm_source_export_run_id, mmm_source_uri, mmm_upstream_tables, mmm_delta_version, mmm_glue_run_id, mmm_script_version, mmm_written_at - data/README.md).",
    "Location s3://lakehouse/<layer>/", s("same"), "lakehouse bucket", DP, INFRA, (CHANGED, "'Data Catalog (Lineage)': lineage table properties written by every job"))
add(L, "Glue", "Glue Data Catalog encryption settings", "account / region setting", ALL1, "S1-4..S1-6", "Encrypts catalog metadata and connection passwords (s3 key). Skip if WBD already manages it.", "SSE-KMS", s("same"), "KMS s3", DP, INFRA)
add(L, "Glue", "Glue security configuration", "mmm-{e}-glue", ALL1, "S1-4..S1-7", "KMS for job S3 output, bookmarks and CloudWatch logs.", "S3 s3 key, logs key", s("same"), "KMS", DP, INFRA)
add(L, "Glue", "Glue connection (NETWORK)", "mmm-{e}-glue-vpc", ALL1, "S1-4..S1-7", "Runs every job in a private app subnet (S3 and Glue API through the VPC endpoints; no database path).", "SG glue", s("same"), "App subnet, SG glue", DP, INFRA,
    (CHANGED, "data-clients SG removed"))
add(L, "IAM", "IAM role - Glue jobs", "mmm-{e}-glue", ALL1, "S1-4..S1-7, S1-13",
    "Read landing raw/databricks/*, read / write lakehouse (incl. rds-export/), write training-data, read scripts + write temp in glue-assets, catalog (incl. table properties for lineage), DQ, BU keys, logs, metrics.",
    "Permission boundary", s("same"), "-", DP, INFRA, (CHANGED, "rds-db:connect removed"))
add(L, "CloudWatch Logs", "Log group - Glue jobs", "/aws-glue/jobs/mmm-{e}", ALL1, "P-2", "Continuous logging of every Glue job.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "Glue", "Glue Data Quality ruleset - silver", "mmm-{e}-silver", ALL1, "S1-5", "Rules evaluated in the silver job; a failure stops the refresh and alerts.", "DQDL rules from the data engineers", s("same"), "Catalog silver", DP, INFRA)
for job, what, flow in (
    ("bronze", "Raw Databricks Parquet -> Bronze Delta tables (job bookmarks)", "S1-4"),
    ("silver", "Cleanse, conform and validate (Data Quality) -> Silver", "S1-5"),
    ("gold", "Per-BU modeling tables (adstock, saturation) -> Gold", "S1-6"),
    ("export-training", "Gold -> immutable Parquet + metadata.json in training-data/<bu>/<refresh_id>/", "S1-7"),
    ("export-rds", "Gold reference tables -> Parquet in lakehouse/rds-export/<bu>/<refresh_id>/ + _manifest.json; the results/data publisher loads them into RDS", "S1-7"),
    ("export-monitor", "Latest features -> lakehouse/monitoring/<bu>/<date>/ for the drift check", "S1-12"),
):
    add(L, "Glue", f"Glue job - {job}", "mmm-{e}-glue-" + job, ALL1, flow, what + ".",
        "Glue 5.0 Spark, --datalake-formats delta, connection glue-vpc, security config, timeout 120 min, script s3://glue-assets/scripts/" + job + ".py",
        s("G.1X x 2 workers", "G.1X x 5 workers", "G.1X x 10 workers"), "Role, connection, glue-assets", DP, INFRA_PIPE,
        (CHANGED, "Writes to S3 instead of RDS (no JDBC, no mmm_etl)") if job == "export-rds" else (SAME, ""))
add(L, "Glue", "Data lineage records (Glue + SageMaker ML Lineage Tracking)", "per refresh: contexts / artifacts / associations", s("per refresh"), "S1-13",
    "Links Databricks export run -> raw files -> Bronze / Silver / Gold table versions -> training-data snapshot -> training job -> model package; queryable from SageMaker lineage.",
    "Written by the model-refresh workflow (no resource to pre-create; IAM on the refresh role)", s("same"), "Refresh state machine role", RUN, "Model-refresh workflow (DevOps)",
    (NEW, "Slide 1 'Data Catalog (Lineage)' and 'Registry + S3 ... + lineage'"))
add(L, "DataZone", "Amazon DataZone / SageMaker Catalog domain (lineage graph)", "mmm-{e}-catalog", ALL1, "S1-13",
    "Optional: visual end-to-end lineage graph and business catalog (Glue 5.0 jobs emit OpenLineage events to the domain).", "Domain + project + Glue data source; KMS s3",
    s("if required"), "Glue Data Catalog", OPT, INFRA, (NEW, "Only if WBD wants a lineage UI beyond the Glue catalog + SageMaker lineage"))

L = "16. SageMaker modeling (slide 1)"
add(L, "IAM", "IAM role - SageMaker training / evaluation / drift", "mmm-{e}-sagemaker-training", ALL1, "S1-8..S1-12", "Read training-data and lakehouse/monitoring, write models, register model packages, VPC ENIs, logs, metrics.", "Permission boundary", s("same"), "-", DP, INFRA)
add(L, "SageMaker", "Model package groups - one per business unit", "mmm-{e}-streaming / -theatrical / -usnetworks", s("3"), "S1-10, S2-6", "Model Registry: every trained version (PendingManualApproval -> Approved); the optimizer reads the approved one.", "-", s("same"), "-", DP, INFRA)
add(L, "CloudWatch Logs", "Log groups - SageMaker TrainingJobs, ProcessingJobs", "/aws/sagemaker/TrainingJobs ; /aws/sagemaker/ProcessingJobs", s("2"), "P-2", "Training, evaluation and drift job logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "SageMaker", "Training job (per refresh)", "mmm-{e}-train-<refresh_id>", s("per refresh"), "S1-8", "Trains the multi-stage model in the VPC; writes the artifact and drift baseline.", "VPC app subnets, SG sagemaker, KMS sagemaker",
    s("ml.m5.2xlarge"), "Training image, role", RUN, DS)
add(L, "SageMaker", "Processing job - evaluation (per refresh)", "mmm-{e}-eval-<bu>-<id>", s("per refresh"), "S1-9", "Baseline -> channel lift -> title adjustment; evaluation.json, curves, predictions, lift.", "VPC, KMS sagemaker",
    s("ml.m5.xlarge"), "Training image, role", RUN, DS)
add(L, "SageMaker", "Processing job - drift (per check)", "mmm-{e}-drift-<bu>-<id>", s("daily per BU"), "S1-12", "Compares the latest features with the baseline; ModelDrift metric.", "VPC, KMS sagemaker", s("ml.m5.xlarge"), "Training image, role", RUN, DS)

L = "17. Model refresh and drift orchestration (slide 1)"
add(L, "Step Functions", "State machine - model refresh", "mmm-{e}-model-refresh", ALL1, "S1-1..S1-13",
    "Export Trigger Lambda (start / status) -> Glue bronze -> silver -> gold -> export-training + export-rds -> publish reference data to RDS (publisher) -> train -> evaluate -> register -> record lineage -> publish model results to RDS.",
    "Standard, logging ALL, X-Ray", s("same"), "Lambdas, Glue jobs, SageMaker role", DP, INFRA,
    (CHANGED, "New states PublishReferenceData (publisher) and RecordLineage"))
add(L, "IAM", "IAM role - model refresh state machine", "mmm-{e}-model-refresh-sfn", ALL1, "S1-1..S1-13",
    "Invoke export + publisher Lambdas, glue:StartJobRun / GetJobRun, SageMaker jobs + registry, SageMaker lineage (CreateContext / CreateArtifact / AddAssociation), PassRole, logs.",
    "Permission boundary", s("same"), "-", DP, INFRA, (CHANGED, "+ SageMaker lineage APIs"))
add(L, "CloudWatch Logs", "Log group - model refresh", "/aws/states/mmm-{e}-model-refresh", ALL1, "P-2", "Refresh execution logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "EventBridge Scheduler", "Schedule group + schedules - refresh per BU", "mmm-{e}-model-refresh ; mmm-{e}-refresh-<bu>", s("4"), "S1-1", "Starts the weekly refresh per business unit.", "Timezone America/New_York",
    s("cron(0 6 ? * MON *) - off until data is ready"), "State machine", DP, INFRA)
add(L, "EventBridge", "Rule - model refresh on demand + IAM trigger role", "mmm-{e}-model-refresh-on-demand ; mmm-{e}-model-refresh-trigger", s("2"), "S1-1", "Manual / app / drift request (event mmm.refresh) starts a refresh for one BU.", "Event pattern source mmm.refresh", s("same"), "State machine", DP, INFRA)
add(L, "EventBridge", "Rule - model package state change", "mmm-{e}-model-package-state", ALL1, "S1-10", "Model version created, approved or rejected -> SNS alerts.", "-", s("same"), "SNS", DP, INFRA)
add(L, "EventBridge", "S3 EventBridge notifications (landing bucket)", "landing bucket setting", ALL1, "S1-3", "'New file' events from landing (optional refresh trigger).", "EventBridge on", s("same"), "landing bucket", DP, INFRA)
add(L, "Step Functions", "State machine - model monitor (drift)", "mmm-{e}-model-monitor", ALL1, "S1-12",
    "Per BU: Databricks export + Glue layers + export-monitor -> SageMaker drift job -> optional mmm.refresh when drift > threshold.", "Standard, logging ALL", s("same"), "Glue, SageMaker", DP, INFRA)
add(L, "IAM", "IAM role - model monitor state machine", "mmm-{e}-model-monitor-sfn", ALL1, "S1-12", "Glue + Lambda + SageMaker processing, PassRole, PutEvents, logs.", "Permission boundary", s("same"), "-", DP, INFRA)
add(L, "CloudWatch Logs", "Log group - model monitor", "/aws/states/mmm-{e}-model-monitor", ALL1, "P-2", "Monitor execution logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "EventBridge Scheduler", "Schedule group + schedules - drift per BU", "mmm-{e}-model-monitor ; mmm-{e}-drift-<bu>", s("4"), "S1-12", "Daily drift check per business unit.", "Off until the first approved model",
    s("cron(0 7 * * ? *)"), "State machine", DP, INFRA)

L = "18. GenAI explanation (slide 2)"
add(L, "API Gateway", "Private REST API - LLM gateway (+ resource, method, integration, deployment, stage v1, method settings)", "mmm-{e}-llm-gateway", s("7"), "S2-9",
    "Single entry from the API's LangGraph explanation tool to the LLM providers.", "Private endpoint (execute-api VPC endpoint), IAM auth, stage throttling, access logs", s("same"), "execute-api endpoint", GENAI, INFRA,
    (SAME, "Slide 2 marks the GenAI box 'Not part of R1' - confirms Release 2 for the whole layer"))
add(L, "API Gateway", "API Gateway account setting + CloudWatch role", "mmm-{e}-apigw-cloudwatch", s("2"), "P-2", "Lets API Gateway write logs (account / region setting).", "-", s("same"), "-", GENAI, INFRA)
add(L, "Lambda", "Lambda - LLM proxy (+ invoke permission)", "mmm-{e}-llm-gateway", s("2"), "S2-9", "Adds the provider key, applies the Bedrock guardrail to prompt and answer, counts tokens per BU.",
    "Python 3.12, 512 MB, 30 s, VPC (SG genai)", s("reserved 20", "reserved 20", "reserved 50"), "Secrets llm/*, guardrail", GENAI, INFRA_PIPE)
add(L, "IAM", "IAM role - LLM proxy", "mmm-{e}-llm-gateway-lambda", ALL1, "S2-9", "Read llm/* secrets and SSM genai/*, bedrock:ApplyGuardrail, metrics, logs.", "Permission boundary", s("same"), "-", GENAI, INFRA)
add(L, "CloudWatch Logs", "Log groups - LLM gateway access + proxy", "/aws/apigateway/mmm-{e}-llm-gateway ; /aws/lambda/mmm-{e}-llm-gateway", s("2"), "P-2", "Gateway access and proxy logs.", "KMS genai", s("30 d", "90 d", "365 d"), "KMS genai", GENAI, INFRA)
add(L, "Bedrock", "Bedrock guardrail + version", "mmm-{e}-genai (v1)", s("2"), "S2-9", "Prompt-attack filter, PII masking / blocking, denied topics, grounding and relevance checks for every provider.",
    "Grounding 0.75, relevance 0.75", s("same"), "KMS genai", GENAI, INFRA)

L = "19. Monitoring, alerting and logging"
add(L, "SNS", "SNS topic - alerts + policy + email subscription", "mmm-{e}-alerts", s("3"), "P-2", "Receives every alarm and alert rule; emails on-call (Teams / paging if WBD adds it).", "KMS alerts",
    s("devops alerts list", "devops alerts list", "on-call list"), "KMS alerts", CORE, INFRA)
add(L, "CloudWatch", "CloudWatch alarms (core)", "see sheet alarms_and_events", s("21"), "P-2", "API, availability, RDS, run queue, Step Functions optimization, publisher, certificate expiry.", "Actions to SNS alerts", s("same"), "SNS", CORE, INFRA)
add(L, "CloudWatch", "CloudWatch alarms (data platform)", "see sheet alarms_and_events", s("9"), "P-2", "Refresh / monitor failures, refresh overdue, model drift per BU, Databricks export errors, lineage not recorded per BU.", "Actions to SNS alerts", s("same"), "SNS", DP, INFRA)
add(L, "CloudWatch", "CloudWatch alarms (GenAI)", "see sheet alarms_and_events", s("7"), "P-2", "Gateway 4xx / 5xx / latency, guardrail interventions, token quota per BU.", "Actions to SNS alerts", s("same"), "SNS", GENAI, INFRA)
add(L, "EventBridge", "EventBridge alert rules -> SNS", "see sheet alarms_and_events", s("8"), "P-2", "GuardDuty high, break-glass used, ECS deployment failed / service error, optimizer task not started, backup failed, Glue job failed, Glue DQ failed.", "Targets SNS alerts", s("same"), "SNS, CloudTrail", CORE, INFRA)
add(L, "CloudWatch", "CloudWatch dashboards", "mmm-{e}-platform / -api-ui / -optimization / -rds / -cost / -data-pipeline / -training / -genai", s("8"), "P-2",
    "Operations views: platform health, API / UI, optimization runs and queue, database, cost, data pipeline (export, Glue, DQ), training, GenAI.", "-", s("same"), "-", CORE, INFRA)
add(L, "CloudWatch Logs", "Logs data protection policy (account)", "mmm-{e}-data-protection", ALL1, "P-2", "Masks personal data (emails, names) if it appears in logs.", "Account policy", s("same"), "-", CORE, INFRA)
add(L, "Kinesis Data Firehose", "Firehose to Splunk + IAM roles + log group / stream", "mmm-{e}-splunk ; mmm-{e}-firehose-splunk ; mmm-{e}-logs-to-firehose", s("5"), "P-2",
    "Ships all log groups to WBD Splunk; failed records to the logs bucket (splunk-failed/).", "HEC endpoint + token secret splunk/hec", s("if Splunk is required"), "Secret splunk/hec", OPT, INFRA)
add(L, "CloudWatch Logs", "Subscription filters -> Firehose", "mmm-{e}-splunk (one per log group)", s("19"), "P-2", "api, ui, migrate, optimizer, publisher, dispatcher, export, Glue, SageMaker, Step Functions, RDS, VPC flow, WAF, ECS Exec, LLM.", "-", s("same"), "Firehose", OPT, INFRA)
add(L, "CloudWatch", "Container Insights (enhanced)", "cluster setting", ALL1, "P-2", "Health and usage of ECS services and optimizer tasks.", "On", s("same"), "ECS cluster", CORE, INFRA)
add(L, "CloudWatch", "Application Signals", "account setting", ALL1, "P-2", "API latency, errors and traces.", "-", s("optional"), "-", OPT, INFRA)

L = "20. Backup and DR"
add(L, "Backup", "AWS Backup vault + policy", "mmm-{e}-vault", s("2"), "P-4", "Encrypted store for daily backups of RDS and the data buckets.", "KMS backup; vault lock in prod if approved", s("same"), "KMS backup", CORE, INFRA)
add(L, "Backup", "AWS Backup plan - daily", "mmm-{e}-daily", ALL1, "P-4", "Daily backups; monthly kept 1 year in prod.", "Daily 05:00 UTC",
    s("keep 7 d", "keep 14 d", "keep 35 d + monthly 365 d"), "Vault", CORE, INFRA)
add(L, "Backup", "Backup selection by tag + IAM role", "mmm-{e}-tag-backup ; role mmm-{e}-backup", s("2"), "P-4",
    "Selects resources tagged backup=true: RDS, results, approved-worm, models, training-data, lakehouse (uploads and glue-assets are not backed up).", "AWS managed backup / restore policies (incl. S3)", s("same"), "Vault", CORE, INFRA)
add(L, "EventBridge", "Rule - backup job failed", "mmm-{e}-backup-job-failed", ALL1, "P-4", "Backup, copy or restore job failed -> SNS.", "-", s("same"), "SNS", CORE, INFRA)
add(L, "Backup", "DR vault (us-west-2) + lock + cross-region copy", "mmm-{e}-vault-dr", s("3"), "P-4", "Copy of the backups in the DR region.", "KMS backup-dr", s("-", "-", "if approved"), "KMS backup-dr", OPT, INFRA)

ALARMS = [
    ("Alarm", "mmm-{e}-api-5xx-rate", "API 5xx > 2% of requests in 3 of 5 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-availability", "Availability < 99.5% in the last hour (5xx from the targets or the ALB)", "S2-1", CORE),
    ("Alarm", "mmm-{e}-api-no-healthy-targets", "api target group has no healthy task - the API is down", "S2-2", CORE),
    ("Alarm", "mmm-{e}-ui-no-healthy-targets", "ui target group has no healthy task - the web app is down", "S2-2", CORE),
    ("Alarm", "mmm-{e}-cert-expiry-alb", "ACM certificate expires in < 30 days (renewal is failing - check DNS validation)", "S2-1", CORE),
    ("Alarm", "mmm-{e}-whatif-p95", "What-if simulation p95 > 10 s for 3 of 5 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-optimization-standard-p95", "Standard optimization runs p95 > 120 s for 3 of 6 periods of 5 minutes", "S2-6", CORE),
    ("Alarm", "mmm-{e}-optimization-runtime-max", "An optimization execution took > 10 minutes (large-run limit)", "S2-6", CORE),
    ("Alarm", "mmm-{e}-optimization-failed", "Optimization execution failed, timed out or was aborted", "S2-6", CORE),
    ("Alarm", "mmm-{e}-optimization-throttled", "Optimization executions were throttled", "S2-5", CORE),
    ("Alarm", "mmm-{e}-results-publisher-errors", "Results publisher returned errors", "S2-8", CORE),
    ("Alarm", "mmm-{e}-runs-dispatcher-errors", "Run dispatcher failed", "S2-5", CORE),
    ("Alarm", "mmm-{e}-runs-dispatcher-throttles", "Run dispatcher throttled", "S2-5", CORE),
    ("Alarm", "mmm-{e}-runs-dlq-not-empty", "Run requests in the DLQ - they failed 10 times", "S2-4", CORE),
    ("Alarm", "mmm-{e}-runs-expired-requests", "Run requests waited longer than 30 minutes and were dropped", "S2-4", CORE),
    ("Alarm", "mmm-{e}-runs-oldest-request", "A run request has waited more than 15 minutes", "S2-4", CORE),
    ("Alarm", "mmm-{e}-rds-cpu", "RDS CPU > 80% for 15 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-rds-connections", "RDS connections > 80% of max_connections for 10 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-rds-free-storage", "RDS free storage < 20 GiB for 15 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-rds-read-latency", "RDS read latency > 20 ms for 15 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-rds-write-latency", "RDS write latency > 20 ms for 15 minutes", "S2-2", CORE),
    ("Alarm", "mmm-{e}-model-refresh-failed", "Model refresh execution failed, timed out or was aborted", "S1-1", DP),
    ("Alarm", "mmm-{e}-model-refresh-throttled", "Model refresh executions were throttled", "S1-1", DP),
    ("Alarm", "mmm-{e}-model-refresh-overdue", "No model refresh succeeded in 7 days", "S1-1", DP),
    ("Alarm", "mmm-{e}-model-monitor-failed", "Model monitor execution failed, timed out or was aborted", "S1-12", DP),
    ("Alarm", "mmm-{e}-model-monitor-throttled", "Model monitor executions were throttled", "S1-12", DP),
    ("Alarm", "mmm-{e}-model-drift-<bu> (x3)", "Model drift for the business unit above 0.2 (one alarm per BU)", "S1-12", DP),
    ("Alarm", "mmm-{e}-databricks-export-errors", "Databricks export Lambda failed in 2 of the last 3 periods of 5 minutes", "S1-2", DP),
    ("Alarm", "mmm-{e}-lineage-record-failed-<bu> (x3)", "The refresh registered a model but could not record its SageMaker ML Lineage (metric MMM/Models LineageRecordFailed)", "S1-13", DP),
    ("Alarm", "mmm-{e}-llm-gateway-4xx", "LLM gateway 4xx > 20 in 5 minutes", "S2-9", GENAI),
    ("Alarm", "mmm-{e}-llm-gateway-5xx", "LLM gateway 5xx (provider down, timeout or proxy error)", "S2-9", GENAI),
    ("Alarm", "mmm-{e}-llm-gateway-latency-p95", "LLM gateway p95 latency > 30 s for 3 of 5 periods", "S2-9", GENAI),
    ("Alarm", "mmm-{e}-genai-guardrail-interventions", "Guardrail blocked more than 25 requests / answers in 15 minutes", "S2-9", GENAI),
    ("Alarm", "mmm-{e}-genai-tokens-<bu> (x3)", "GenAI tokens of the BU > 80% of the daily quota (one alarm per BU)", "S2-9", GENAI),
    ("Alarm", "mmm-{e}-splunk-delivery", "Splunk rejects or cannot be reached", "P-2", OPT),
    ("Alarm", "mmm-{e}-splunk-freshness", "Oldest record not yet in Splunk > 15 minutes", "P-2", OPT),
    ("Event rule", "mmm-{e}-guardduty-high", "GuardDuty finding with severity >= 7", "P-1", CORE),
    ("Event rule", "mmm-{e}-breakglass-used", "BreakGlass permission set used - needs an incident ticket", "P-1", CORE),
    ("Event rule", "mmm-{e}-ecs-deployment-failed", "ECS deployment failed - the circuit breaker rolled the service back", "S2-2", CORE),
    ("Event rule", "mmm-{e}-ecs-service-error", "ECS service cannot start or place tasks (image pull, secrets, capacity)", "S2-2", CORE),
    ("Event rule", "mmm-{e}-optimizer-task-not-started", "Optimizer task failed to start (Fargate vCPU quota, image pull or network)", "S2-6", CORE),
    ("Event rule", "mmm-{e}-backup-job-failed", "AWS Backup job failed, aborted or expired", "P-4", CORE),
    ("Event rule", "mmm-{e}-glue-job-failed", "A Glue job failed or timed out", "S1-4..S1-7", DP),
    ("Event rule", "mmm-{e}-glue-data-quality-failed", "Glue Data Quality rules failed in the Silver layer - the refresh stops", "S1-5", DP),
    ("Event rule", "mmm-{e}-model-package-state", "Model package created, approved or rejected", "S1-10", DP),
    ("Event rule", "mmm-{e}-model-refresh-on-demand", "Start a model refresh for one business unit (not an alert)", "S1-1", DP),
]

# Things outside AWS the infra team needs before / while creating the resources.
OUTSIDE = [
    ("WBD DNS / PKI", "App domain names + ACM certificate validation records", "mmm-dev / mmm-stg / mmm .<wbd domain>", "Before the ALB HTTPS listener"),
    ("WBD Identity", "Okta OIDC app per environment, groups mmm-bu-* / mmm-role-*, client secret into mmm/<env>/okta/alb-client", "Redirect https://<app>/oauth2/idpresponse", "Before sign-in is switched on"),
    ("WBD Databricks admins", "Export job per BU, service principal + OAuth secret, Unity Catalog storage credential + external location, IP access list (NAT IPs)", "Job ids -> /mmm/<env>/databricks/export_job_ids", "Before the first refresh"),
    ("WBD Network", "VPC CIDR, AZ ids, Transit Gateway / resolver details if the VPC joins the WBD network; firewall egress for Databricks, Okta, LLM providers", "10.40.0.0/19 etc.", "Before networking"),
    ("WBD Cloud Platform", "Quota increases (Fargate vCPU, Glue, SageMaker); SCP allows the listed services", "See layer 01", "Before load test / first refresh"),
    ("WBD Splunk", "HEC endpoint + token, index, source type", "Secret mmm/<env>/splunk/hec", "Only if Splunk shipping is required"),
    ("GitHub admins", "Repository, environments dev / staging / prod, approvers; OIDC trust subject org/repo", "Role ARNs from layer 04 into GitHub variables", "Before the first deploy"),
    ("Data engineers", "Glue job scripts and Silver DQ rules (data/glue/)", "Uploaded to s3://glue-assets/scripts/", "Before the first refresh"),
    ("Data science", "Optimizer image and training image", "Pushed to ECR mmm/optimizer, mmm/sagemaker-training", "Before the first run / refresh"),
    ("Backend team", "DB migrations (tables incl. Gold reference + model results, row-level security), DB users mmm_app / mmm_migrator; publisher code for reference_data", "Run by the migrate task", "Before the API goes live"),
    ("WBD Security / Audit", "CloudTrail S3 data-event selectors on the MMM buckets in the org trail", "Bucket names from layer 09", "Before production data arrives"),
]

# v4 resources (built in the repo) that v5 removes.
REMOVED = [
    ("08. Secrets and parameters", "Secret mmm/<env>/rds/etl", "Glue no longer connects to RDS; the results/data publisher (mmm_app) writes the Gold reference tables"),
    ("10. Database", "DB user mmm_etl (db-bootstrap ETL_SECRET_ID) and its RDS Proxy auth entry", "Same reason"),
    ("06. Security groups", "Glue jobs in the data-clients SG (5432 to RDS Proxy)", "Glue has no database path"),
    ("15. AWS Glue", "Glue role rds-db:connect as mmm_etl; JDBC write in export-rds", "export-rds writes Parquet to lakehouse/rds-export/"),
]

# (layer, what changes in the v4 code, why - slide reference)
CODE_IMPACT = [
    ("data.tf / modules/glue", "export-rds job: output lakehouse/rds-export/<bu>/<refresh_id>/; connection without data-clients; role without rds-db:connect", "Slide 1: Glue Export -> Lambda results/data publisher -> RDS"),
    ("data.tf (model-refresh)", "New states PublishReferenceData (publisher event reference_data) after the exports, RecordLineage after RegisterModel; role + sagemaker lineage APIs", "Slide 1 arrows + 'lineage'"),
    ("optimization.tf (publisher)", "Publisher role reads lakehouse/rds-export/* + BU keys; timeout for large reference tables", "Results/data publisher"),
    ("main.tf / rds", "Remove secret rds/etl and its proxy auth; lakehouse prefix expiry rds-export/ 30 d", "No Glue DB client"),
    ("scripts/db-bootstrap.py", "Remove mmm_etl", "No Glue DB client"),
    ("data/README.md, apps contract", "reference_data event contract; lineage table properties written by the Glue scripts", "Data engineers / backend"),
    ("monitoring", "Alarm on publisher reference_data failures (refresh fails) - covered by the refresh failed alarm; data-pipeline dashboard shows rows published", "Observability"),
    ("docs / runbooks", "10, 05, 06, model-refresh-failed, glue-job-failed, rotation (no rds/etl); GenAI marked Release 2 only", "Slide 2 'Not part of R1'"),
    ("Optional", "CloudTrail data events (WBD org trail), DataZone lineage domain - only if WBD confirms", "Environment-level box, lineage"),
]

HEAD = PatternFill("solid", fgColor="1F3864")


def release(scope):
    return "Release 2" if scope == GENAI else "Release 1"
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(vertical="top", wrap_text=True)


def style_header(ws, row):
    for c in ws[row]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD
        c.border = BORDER
        c.alignment = Alignment(vertical="center", wrap_text=True)


def style_body(ws, fill=None):
    for c in ws[ws.max_row]:
        c.border = BORDER
        c.alignment = WRAP
        if fill:
            c.fill = fill


def widths(ws, values):
    for i, w in enumerate(values, 1):
        ws.column_dimensions[get_column_letter(i)].width = w


def title(ws, text, note):
    ws["A1"] = text
    ws["A1"].font = Font(bold=True, size=13)
    ws["A2"] = note
    ws["A2"].font = Font(italic=True, size=9)
    ws.append([])


def generic(name):
    return name.replace("{e}", "<env>")


def joined(values):
    return values[0] if len(set(values)) == 1 else " / ".join(values)


LEGEND = ("Filter on 'Release' (Release 1 = go-live incl. the slide 1 model refresh; Release 2 = GenAI explanation, 'Not part of R1' "
          "on slide 2), on 'Scope' and on 'Change vs v4' (New / Changed / Same compared with the v4 build in the repo).")


def build_resources():
    wb = Workbook()
    ws = wb.active
    ws.title = "README"
    title(ws, "WBD MMM v5 - complete AWS resource list for the WBD infrastructure team",
          "Source: WBD_MMM_Architecture_5.pptx (slide 1 auto ML activities, slide 2 optimization and explainable planning). "
          "Names follow the v4 build in the repo; 'Change vs v4' shows what v5 changes.")
    for k, v in (
        ("Purpose", "The WBD infrastructure team creates the AWS resources of the MMM platform from this list, in the order of the layers."),
        ("Environments", "Three WBD-owned AWS accounts: dev, staging, prod. Region us-east-1 (DR us-west-2, only if approved)."),
        ("Naming", "Resources: mmm-<env>-<purpose> with <env> = dev / stg / prd. Buckets: wbd-mmm-<env>-<purpose>-use1. "
                   "Secrets: mmm/<env>/<path>. SSM parameters: /mmm/<env>/<path>. KMS aliases: alias/mmm-<env>-<purpose>. Glue databases: mmm_<env>_<layer>."),
        ("Tags (every resource)", "Project = wbd-mmm, Environment = dev / staging / prod, Owner = <WBD team>, CostCenter = <WBD value>, ManagedBy = <tool>; backup = true on RDS and the backed-up buckets."),
        ("Business units", BUS + " (resources marked 'per BU' exist once per business unit)."),
        ("Sheets", "all_resources = complete list with dev / staging / prod values; dev, staging, prod = the same list with the real names of that environment; "
                   "architecture_flow = the v5 flow steps referenced in column 'Flow step'; alarms_and_events = every alarm and alert rule; "
                   "outside_aws = what other WBD teams provide; v5_changes = rows that differ from v4; removed_vs_v4 = v4 resources v5 drops; "
                   "summary = count per layer."),
        ("Release column", "Release 1 = everything needed for go-live (slide 2 optimization + slide 1 auto ML + platform); "
                           "Release 2 = GenAI explanation (API Gateway LLM gateway, Bedrock Guardrails, OpenAI / Anthropic / Google) - slide 2 'Not part of R1'."),
        ("Scope column", f"'{CORE}' = needed for go-live; '{DP}' = slide 1 auto ML (can be created after the core); '{GENAI}'; '{OPT}'; "
                         f"'{BASE}' = should already exist in a WBD account; '{QUOTA}'; '{RUN}' = listed so the flow is complete, not created by the infra team."),
        ("Owner column", "Who creates it. 'first version; new revisions by the deploy pipeline' = the infra team creates the resource once, "
                         "the CI/CD pipeline then deploys new code / task revisions (needs the GitHub roles of layer 04)."),
        ("IAM and KMS", "v5 draws 'AWS IAM' on every integration and 'KMS' on every data store: each arrow is a least-privilege role (listed per resource), "
                        "each store has a customer-managed key (layer 03)."),
        ("Secrets", "Secret values are never in this file or in Git; the owner enters them in Secrets Manager. Placeholders are marked '# add actual value'."),
        ("Legend", LEGEND),
    ):
        ws.append([k, v])
        style_body(ws)
        ws.cell(ws.max_row, 1).font = Font(bold=True)
    widths(ws, (22, 140))

    headers = ["#", "Release", "Layer", "AWS service", "Resource", "Name", "Qty", "Flow step", "What it does in the v5 flow",
               "Key configuration", "Dev", "Staging", "Prod", "Depends on", "Scope", "Created by / owner", "Change vs v4", "v5 change note"]
    ws = wb.create_sheet("all_resources")
    title(ws, "All AWS resources - v5 architecture (dev / staging / prod)",
          "<env> in names = dev / stg / prd. Qty = count in one environment (dev / staging / prod when different). " + LEGEND)
    ws.append(headers)
    style_header(ws, 4)
    for i, (layer, svc, res, name, qty, flow, what, cfg, per_env, dep, scope, owner, chg) in enumerate(R, 1):
        ws.append([i, release(scope), layer, svc, res, generic(name), joined(qty), flow, what, cfg, *per_env, dep, scope, owner, *chg])
        style_body(ws)
    widths(ws, (5, 11, 22, 16, 34, 38, 9, 12, 60, 46, 20, 20, 22, 22, 24, 24, 12, 44))
    ws.freeze_panes = "F5"
    ws.auto_filter.ref = f"A4:{get_column_letter(len(headers))}{ws.max_row}"

    for env, short, label in ENVS:
        ws = wb.create_sheet(env)
        title(ws, f"{label} - AWS resources to create (v5 architecture)",
              f"Real names for {label} (<env> = {short}). Setting = the {label} value. " + LEGEND)
        ws.append(["#", "Release", "Layer", "AWS service", "Resource", f"Name ({label})", "Qty", "Flow step", "What it does in the v5 flow",
                   "Key configuration", f"{label} setting", "Depends on", "Scope", "Created by / owner", "Change vs v4",
                   "Created (Y/N)", "ARN / ID", "Notes"])
        style_header(ws, 4)
        idx = ("dev", "staging", "prod").index(env)
        for i, (layer, svc, res, name, qty, flow, what, cfg, per_env, dep, scope, owner, chg) in enumerate(R, 1):
            ws.append([i, release(scope), layer, svc, res, name.replace("{e}", short), qty[idx], flow, what, cfg, per_env[idx], dep, scope, owner,
                       chg[0], "", "", ""])
            style_body(ws)
        widths(ws, (5, 11, 22, 16, 34, 40, 9, 12, 60, 46, 24, 22, 24, 24, 12, 10, 30, 24))
        ws.freeze_panes = "F5"
        ws.auto_filter.ref = f"A4:R{ws.max_row}"

    ws = wb.create_sheet("architecture_flow")
    title(ws, "v5 architecture flow - steps referenced in the resource list",
          "Slide 1 = auto ML activities (model refresh); slide 2 = optimization and explainable planning; Platform = cross-cutting bands.")
    ws.append(["Step", "Slide", "Step name", "What happens", "Resources used (rows on all_resources)"])
    style_header(ws, 4)
    for step, slide, name, text in FLOW:
        used = [str(i) for i, r in enumerate(R, 1) if step in flow_steps(r[5])]
        ws.append([step, slide, name, text, ", ".join(used)])
        style_body(ws)
    widths(ws, (8, 22, 30, 100, 40))
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A4:E{ws.max_row}"

    ws = wb.create_sheet("alarms_and_events")
    title(ws, "CloudWatch alarms and EventBridge alert rules (all go to SNS mmm-<env>-alerts)",
          "Thresholds are the defaults of the code; dev / staging / prod use the same rules. Publisher reference_data failures fail the refresh (model-refresh-failed).")
    ws.append(["#", "Release", "Type", "Name", "Fires when", "Flow step", "Scope"])
    style_header(ws, 4)
    for i, (kind, name, when, flow, scope) in enumerate(ALARMS, 1):
        ws.append([i, release(scope), kind, generic(name), when, flow, scope])
        style_body(ws)
    widths(ws, (5, 11, 12, 44, 80, 12, 40))
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A4:G{ws.max_row}"

    ws = wb.create_sheet("outside_aws")
    title(ws, "Provided by other WBD teams (needed to finish the resources above)", "Not AWS resources the infra team creates, but inputs they depend on.")
    ws.append(["#", "Team", "What", "Detail", "Needed"])
    style_header(ws, 4)
    for i, row in enumerate(OUTSIDE, 1):
        ws.append([i, *row])
        style_body(ws)
    widths(ws, (5, 22, 80, 50, 32))
    ws.auto_filter.ref = f"A4:E{ws.max_row}"

    ws = wb.create_sheet("v5_changes")
    title(ws, "Rows that differ from the v4 build (WBD_MMM_Architecture_4.pptx -> _5.pptx)", "Row numbers match all_resources.")
    ws.append(["#", "Release", "Layer", "Resource", "Name", "Change vs v4", "What changes"])
    style_header(ws, 4)
    for i, r in enumerate(R, 1):
        if r[12][0] != SAME or r[12][1]:
            ws.append([i, release(r[10]), r[0], r[2], generic(r[3]), *r[12]])
            style_body(ws)
    widths(ws, (5, 11, 24, 44, 40, 12, 80))
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A4:G{ws.max_row}"

    ws = wb.create_sheet("removed_vs_v4")
    title(ws, "v4 resources (built in the repo) that v5 removes", "To be deleted when v5 is implemented.")
    ws.append(["#", "Layer", "Removed", "Why"])
    style_header(ws, 4)
    for i, row in enumerate(REMOVED, 1):
        ws.append([i, *row])
        style_body(ws)
    widths(ws, (5, 26, 60, 80))

    ws = wb.create_sheet("summary")
    title(ws, "Resource count per layer", "Rows of all_resources per layer and scope. AWS objects = sum of Qty in prod "
          "(without account baseline, quotas and run-time objects; settings such as lifecycle or bucket policy are part of their resource).")
    scopes = (CORE, DP, GENAI, OPT, BASE, QUOTA, RUN)
    ws.append(["Layer", "Rows", "Release 1", "Release 2", "New in v5", "Changed by v5", *scopes, "AWS objects (prod)"])
    style_header(ws, 4)

    def line(label, rows):
        ws.append([label, len(rows), *(sum(1 for r in rows if release(r[10]) == rel) for rel in ("Release 1", "Release 2")),
                   sum(1 for r in rows if r[12][0] == NEW), sum(1 for r in rows if r[12][0] == CHANGED),
                   *(sum(1 for r in rows if r[10] == sc) for sc in scopes), objects(rows)])
        style_body(ws)

    for layer in dict.fromkeys(r[0] for r in R):
        line(layer, [r for r in R if r[0] == layer])
    line("Total", R)
    for c in ws[ws.max_row]:
        c.font = Font(bold=True)
    ws.append(["Removed vs v4", len(REMOVED)])
    style_body(ws)
    widths(ws, (40, 8, 10, 10, 10, 12, 16, 22, 22, 18, 18, 12, 18, 16))

    wb.save(OUT / "aws_resource_list_5.xlsx")


def flow_steps(text):
    """Expands 'S1-4..S1-7, S2-2' into the single step ids."""
    out = set()
    for part in text.replace(" ", "").split(","):
        if ".." in part:
            a, b = part.split("..")
            prefix = a.rsplit("-", 1)[0]
            assert prefix == b.rsplit("-", 1)[0], part
            out.update(f"{prefix}-{n}" for n in range(int(a.rsplit("-", 1)[1]), int(b.rsplit("-", 1)[1]) + 1))
        elif part:
            out.add(part)
    return out


def objects(rows):
    """Sum of the prod quantities, without run-time objects, quotas and baseline settings."""
    return sum(int(r[4][2]) if r[4][2].isdigit() else 1 for r in rows if r[10] not in (RUN, QUOTA, BASE))


# ------------------------------------------------------------------ client questions
# (section, what WBD provides, example / proposed default, used for (aws_resource_list_5.xlsx), WBD owner)
INPUTS = [
    # 1. Provisioning model and ownership
    ("1. Provisioning model", "Who creates the AWS resources of aws_resource_list_5.xlsx: WBD Infra with their own tooling (CloudFormation / Terraform / console) or WBD runs our Terraform", "WBD Infra creates them from aws_resource_list_5.xlsx", "All layers", "Cloud Platform / Infra"),
    ("1. Provisioning model", "How we receive the created resource ARNs / IDs back (needed for app config and GitHub variables)", "Filled 'ARN / ID' column of the dev / staging / prod sheets, or SSM / Terraform outputs", "All layers", "Infra"),
    ("1. Provisioning model", "Naming and tagging standard: accept mmm-<env>-* / wbd-mmm-<env>-*-use1 and the tags in the README sheet, or give the WBD standard", "Project, Environment, Owner, CostCenter, ManagedBy; backup = true", "All resources", "Cloud Platform"),
    ("1. Provisioning model", "Values for the tags Owner and CostCenter per environment", "Owner = <WBD team>, CostCenter = <WBD value>", "All resources", "Finance / Cloud Platform"),
    ("1. Provisioning model", "May the deploy pipeline update ECS services, task definitions, Lambda code and Glue scripts after the first creation ('first version; new revisions by the deploy pipeline')", "Yes - GitHub roles gha-deploy / gha-ecr-push", "04, 11, 13, 14, 15", "Security / Cloud Platform"),
    ("1. Provisioning model", "Timeline and change process for creating the resources per environment (dev first, then staging, then prod)", "One change ticket per environment", "-", "Infra / CAB"),
    # 2. AWS accounts and account baseline (layer 01)
    ("2. AWS accounts and baseline", "AWS account IDs (dev, staging, prod) and account names", "12 digits; wbd-mmm-dev / wbd-mmm-stage / wbd-mmm-prod", "01 AWS account per environment", "Cloud Platform"),
    ("2. AWS accounts and baseline", "Approved primary and DR region (Glue 5.0, SageMaker, Bedrock must be available)", "us-east-1; DR us-west-2", "01, 20", "Cloud Platform"),
    ("2. AWS accounts and baseline", "SCPs allow the services of the list (ECS, Lambda, Step Functions, SQS, Glue, SageMaker, API Gateway, Bedrock, Firehose, Backup, EventBridge Scheduler)", "Confirmation", "01 Service Control Policies", "Cloud Platform"),
    ("2. AWS accounts and baseline", "IAM Identity Center (drawn under Okta on slide 2): is Okta the identity source (SAML + SCIM)? Start URL and the Okta groups mapped to the permission sets", "Okta -> Identity Center; ReadOnly, Developer, DevOps, Security, BreakGlass", "01 Permission sets", "Identity / Cloud Platform"),
    ("2. AWS accounts and baseline", "Access per environment for the DevOps team (prod: time-limited elevation on approval)", "dev + staging DevOps; prod ReadOnly, DevOps on approval", "01 Permission sets", "Security"),
    ("2. AWS accounts and baseline", "Confirm the account baseline is on: CloudTrail org trail (with events to EventBridge), GuardDuty, Security Hub, Config, Inspector (ECR scanning), Access Analyzer, S3 Block Public Access, EBS encryption by default", "Confirmation per account", "01 baseline rows", "Security"),
    ("2. AWS accounts and baseline", "CloudTrail 'to be enabled across all components': add S3 data events for the 7 MMM data buckets to the org trail, or may we create our own trail", "WBD org trail with advanced event selectors; dev write only, staging / prod read + write", "01 CloudTrail S3 data events", "Security / Audit"),
    ("2. AWS accounts and baseline", "Amazon Macie on the data buckets required", "No", "01 Amazon Macie (optional)", "Security"),
    # 3. Service quotas (layer 01)
    ("3. Service quotas", "Fargate On-Demand vCPU quota increase (UI / API services + one optimizer task per run)", ">= 40 / >= 120 / >= 450 vCPU", "01 Fargate On-Demand vCPU", "Cloud Platform"),
    ("3. Service quotas", "AWS Glue concurrent job runs and DPUs", ">= 20 runs; DPUs for 10 workers x 6 jobs", "01 Glue quota", "Cloud Platform"),
    ("3. Service quotas", "SageMaker training and processing instance quotas (ml.m5.2xlarge training, ml.m5.xlarge processing)", ">= 3 each", "01 SageMaker quota", "Cloud Platform"),
    # 4. Terraform state (layer 02)
    ("4. Terraform state", "Is our Terraform used? If yes: may we create the state bucket + KMS key per account, or does WBD provide a state backend", "wbd-mmm-<env>-tfstate-use1 + alias/mmm-<env>-tfstate", "02 Terraform state (optional)", "Infra"),
    # 5. Encryption (layer 03)
    ("5. Encryption (KMS)", "Customer-managed KMS keys per purpose (s3, rds, logs, secrets, ecr, sqs, sagemaker, alerts, backup) and one per business unit - accept, or use WBD central keys", "Keys created per account with rotation on (slides draw KMS on every store)", "03 KMS keys", "Security"),
    ("5. Encryption (KMS)", "Key administrators and the key-policy standard (account root + the roles that use the key)", "WBD Security as key admin", "03 KMS keys", "Security"),
    # 6. IAM foundation, CI/CD access and cost (layer 04)
    ("6. IAM and CI/CD access", "IAM roles: does WBD create the application roles with our policies (slides draw 'AWS IAM' on every integration), and is a WBD permission boundary mandatory", "WBD creates them with mmm-<env>-permission-boundary", "04 + every IAM role", "Security / Infra"),
    ("6. IAM and CI/CD access", "GitHub organization / repository for the OIDC trust (repo + branch / environment)", "wbd-org/wbd-mmm-devops", "04 GitHub OIDC provider + roles", "GitHub admins"),
    ("6. IAM and CI/CD access", "GitHub OIDC identity provider: already in the account or to be created", "Create token.actions.githubusercontent.com", "04 IAM OIDC identity provider", "Security"),
    ("6. IAM and CI/CD access", "Monthly budget per account and the cost-alert recipients", "3,000 / 6,000 / 15,000 USD", "04 AWS Budget, cost anomaly monitor", "Finance"),
    # 7. Networking (layer 05)
    ("7. Networking", "VPC CIDR per environment (no overlap with WBD ranges)", "10.40.0.0/19, 10.40.32.0/19, 10.40.64.0/19", "05 VPC", "Network"),
    ("7. Networking", "Availability Zones", "2 in dev, 3 in staging / prod (use1-az1, az2, az4)", "05 Subnets", "Network"),
    ("7. Networking", "Internet egress: NAT gateways allowed, or central egress / firewall / proxy (Databricks API, Okta, package indexes; LLM providers in Release 2)", "NAT: 1 in dev, 1 per AZ in staging / prod", "05 NAT gateways", "Network"),
    ("7. Networking", "NAT Elastic IPs must be allow-listed anywhere (Databricks workspace IP access list, Okta, vendors)", "Yes - Databricks IP access list", "05 NAT gateways, 14", "Network / Databricks"),
    ("7. Networking", "Connect to the WBD network: Transit Gateway ID and routes", "Not required unless VDI / Splunk / on-prem access is needed", "05 Transit Gateway attachment (optional)", "Network"),
    ("7. Networking", "DNS forwarding to WBD internal domains: domains and resolver IPs", "Not required", "05 Outbound resolver endpoint (optional)", "Network"),
    ("7. Networking", "VPC flow-log retention and destination (CloudWatch or central log archive)", "CloudWatch, 30 / 90 / 365 days", "05 VPC flow logs", "Security"),
    # 8. Security groups and reachability (layer 06)
    ("8. Security groups", "Who may reach the app: internet or only WBD IP ranges (ALB security group source)", "Internet + WAF + Okta sign-in", "06 Security group - alb", "Security / Network"),
    ("8. Security groups", "WBD IP ranges if the app is restricted", "CIDR list", "06 Security group - alb", "Network"),
    # 9. Container registry (layer 07)
    ("9. Container registry", "ECR in each account or a central WBD registry; image retention and scanning standard", "ECR per account: mmm/api, mmm/ui, mmm/optimizer, mmm/sagemaker-training; keep last 20 tags; enhanced scanning", "07 ECR", "Cloud Platform / Security"),
    ("9. Container registry", "Approved base images (Python, Node, nginx) or a WBD golden-image registry", "Official slim images", "07 ECR, CI", "Security"),
    # 10. Secrets and parameters (layer 08)
    ("10. Secrets and parameters", "Who enters each secret value in Secrets Manager (never by email): Okta client secret, Databricks export service principal, Splunk HEC token, vendor keys", "Owner team per secret (see 'Created by / owner')", "08 Secrets", "Identity / Databricks / Splunk"),
    ("10. Secrets and parameters", "Secret rotation policy (DB users, Okta client secret, Databricks service-principal secret)", "DB every 90 days; others yearly or per WBD policy", "08 Secrets", "Security"),
    ("10. Secrets and parameters", "Third-party vendor data still needed (API keys entered by WBD)", "adstra, inscape / none", "08 Secret - thirdparty/* (optional)", "Data owners"),
    # 11. Storage (layer 09)
    ("11. Storage (S3)", "Retention per bucket: landing (Glacier after 365 d), training data (Object Lock), uploads, exports, logs", "Training data 365 d (prod 730 d COMPLIANCE); uploads 90 d; exports 30 d; logs 90 / 365 d", "09 S3 buckets", "Legal / Audit"),
    ("11. Storage (S3)", "Approved scenarios: Object Lock mode and retention (must be set when the bucket is created)", "GOVERNANCE in dev / staging, COMPLIANCE in prod, 7 years", "09 S3 bucket - approved-worm", "Legal / Audit"),
    ("11. Storage (S3)", "User file upload to S3 (slide 2): accepted file types, maximum file size", "xlsx / csv, 50 MB; browser PUT with a presigned URL", "09 S3 bucket - uploads", "Product"),
    ("11. Storage (S3)", "'Upload future titles' file template and the columns required", "Template xlsx", "09 uploads, API contract", "Product / Data science"),
    ("11. Storage (S3)", "Malware scanning of user uploads required (GuardDuty Malware Protection for S3)", "No", "09 Malware Protection for S3 (optional)", "Security"),
    # 12. Database (layer 10)
    ("12. Database", "RDS PostgreSQL size per environment (instance, storage, Multi-AZ, read replica)", "dev db.t4g.medium single-AZ 50 GB; staging db.r6g.large Multi-AZ 100 GB; prod db.r6g.xlarge Multi-AZ 200 GB; no replica", "10 RDS for PostgreSQL instance", "Architecture / Ops"),
    ("12. Database", "PostgreSQL version standard", "16.x", "10 DB parameter group, instance", "Ops"),
    ("12. Database", "Backup retention and maintenance / backup windows", "PITR 7 / 14 / 35 days; Sunday maintenance", "10 instance, 20", "Ops"),
    ("12. Database", "Who creates the DB users mmm_app (API + results/data publisher) and mmm_migrator and enters their secrets", "DevOps DB bootstrap task after the instance exists", "10 DB users, 08 secrets", "Infra / DevOps"),
    ("12. Database", "Who may connect to the database for support (read-only role, through which path)", "No direct access; ECS Exec on the platform-check task in dev / staging only", "10, 11", "Security / Ops"),
    # 13. ECS UI and API (layer 11)
    ("13. ECS UI and API", "API / UI task counts and sizes per environment", "api 1 vCPU / 2 GB, 1-2 / 2-4 / 3-10 tasks; ui 0.25 vCPU / 0.5 GB, 1-2 / 2-3 / 2-6 tasks", "11 ECS services, task definitions", "Architecture"),
    ("13. ECS UI and API", "Fargate Spot allowed in dev / staging", "Yes for dev; no for prod", "11 ECS cluster", "Cloud Platform"),
    ("13. ECS UI and API", "ECS Exec allowed (audited) for troubleshooting", "dev / staging only", "11 ECS cluster, log group exec-audit", "Security"),
    # 14. Front door and sign-in (layer 12)
    ("14. Front door and sign-in", "App domain name per environment (also the only CORS origin of the uploads bucket)", "mmm-dev.<domain>, mmm-stg.<domain>, mmm.<domain>", "12 ACM certificate, DNS record; 09 uploads", "DNS"),
    ("14. Front door and sign-in", "ACM certificate in us-east-1 (or WBD-issued) and the DNS record to the ALB (WBD DNS or a Route 53 zone we may use)", "ACM DNS-validated; CNAME in WBD DNS", "12 ACM certificate, DNS record", "DNS / PKI"),
    ("14. Front door and sign-in", "Okta OIDC web app per environment: issuer URL and client ID (redirect https://<app>/oauth2/idpresponse)", "https://wbd.okta.com/oauth2/default, 0oa...", "12 Okta OIDC app, 08 okta/issuer", "Identity"),
    ("14. Front door and sign-in", "Okta group names for business unit and role (groups claim in the ID token, used for RBAC)", "mmm-bu-streaming, mmm-role-planner, mmm-role-approver", "12, API RBAC", "Identity"),
    ("14. Front door and sign-in", "Session length; MFA / step-up for approvals", "12 hours; MFA per WBD policy", "12 Okta OIDC app", "Identity"),
    ("14. Front door and sign-in", "WAF policy: rate limit, managed rule sets, country allow-list, Shield Advanced", "2000 requests / 5 min per IP; AWS managed rules; no geo block; no Shield Advanced", "12 WAF web ACL", "Security"),
    # 15. Optimization engine (layer 13)
    ("15. Optimization engine", "Optimizer task size and maximum run time", "4 vCPU / 16 GB / 50 GiB (prod 8 vCPU / 32 GB); 60 minutes", "13 ECS task definition - optimizer", "Data science"),
    ("15. Optimization engine", "Runs allowed at the same time per environment and maximum queue wait", "5 / 20 / 50 runs; 30 minutes", "08 max_concurrent_runs, 13", "Business / EY"),
    ("15. Optimization engine", "Expected planners and runs per day in peak planning season", "50-150 planners; runs per day per BU", "13, 01 Fargate quota", "Business"),
    ("15. Optimization engine", "Run types: optimize (upload inventory + objective) and forecast (upload future titles) - any other", "optimize, forecast", "13, API contract", "Product"),
    ("15. Optimization engine", "Size of the Gold reference data loaded into RDS by the results/data publisher per refresh (rows / MB per BU) - decides the publisher timeout", "< 1 GB per BU; publisher 512 MB / 120 s, 900 s if needed", "13 Lambda - results/data publisher", "Data engineering / Backend"),
    # 16. Databricks export (layer 14)
    ("16. Databricks export", "Databricks workspace URL and account ID per environment", "https://dbc-....cloud.databricks.com", "08 databricks/host, 14", "Databricks"),
    ("16. Databricks export", "Source catalog / schema / tables per business unit (3+ years historical inventory), size and growth", "wbd_prod.mmm.<table>; GB per BU", "14, 15 Glue sizing", "Databricks / Data owners"),
    ("16. Databricks export", "Export job ID per business unit and the job owner (the job writes Parquet to the output URI it receives)", '{"streaming": 123, ...}', "14 Databricks export job, 08 export_job_ids", "Databricks / Data"),
    ("16. Databricks export", "Service principal for the Export Trigger Lambda ('Can manage run'): client ID + OAuth secret entered in Secrets Manager by WBD", "mmm/<env>/databricks/export-sp", "14 Service principal, 08 secret", "Databricks"),
    ("16. Databricks export", "Unity Catalog storage credential + external location on landing raw/databricks/ using role mmm-<env>-databricks-uc (we give the role ARN and external ID)", "Registered by the Databricks admins", "14 IAM role - Databricks UC", "Databricks"),
    ("16. Databricks export", "Databricks reachability: workspace IP access list allows our NAT IPs, or PrivateLink (service name)", "NAT IPs from layer 05", "05, 14", "Databricks / Network"),
    ("16. Databricks export", "Export window and expected export duration per BU", "Monday 05:00-06:00 ET; < 30 minutes", "14, 17 schedules", "Databricks"),
    # 17. Glue lakehouse and lineage (layer 15)
    ("17. Glue lakehouse and lineage", "Glue version and worker size per environment", "Glue 5.0; G.1X x 2 / 5 / 10; 120-minute timeout", "15 Glue jobs", "Data / Architecture"),
    ("17. Glue lakehouse and lineage", "Is the Glue Data Catalog encryption (account-wide setting) already managed by WBD", "No - created with this list", "15 Glue Data Catalog encryption", "Cloud Platform / Security"),
    ("17. Glue lakehouse and lineage", "AWS Lake Formation required, or IAM only", "IAM only", "15", "Security / Data"),
    ("17. Glue lakehouse and lineage", "Silver data-quality rules, their owner and behaviour on failure", "DQDL rules from the data engineers; stop the refresh and alert", "15 Glue Data Quality ruleset", "Data engineering"),
    ("17. Glue lakehouse and lineage", "Gold tables needed by the app in RDS: list, size per BU, full reload or incremental", "<bu>_titles, <bu>_inventory_history; full reload per refresh", "15 export-rds, 13 publisher", "Data / Backend"),
    ("17. Glue lakehouse and lineage", "Data lineage ('Data Catalog (Lineage)', 'Registry + S3 ... + lineage'): what must be traceable and who reviews it", "Databricks export run -> Glue tables -> training snapshot -> training job -> model version", "15 Data lineage records", "Data governance / Data science"),
    ("17. Glue lakehouse and lineage", "Lineage / catalog UI required (Amazon DataZone / SageMaker Catalog)", "Not required", "15 DataZone domain (optional)", "Data governance"),
    # 18. SageMaker modeling (layer 16)
    ("18. SageMaker modeling", "Training and processing instance types, maximum training time", "ml.m5.2xlarge training, ml.m5.xlarge evaluation / drift; 4 hours", "16 Training / processing jobs", "Data science"),
    ("18. SageMaker modeling", "Business unit names (one model package group each)", "streaming, theatrical, usnetworks", "16 Model package groups, 03 per-BU keys", "Data"),
    ("18. SageMaker modeling", "Model acceptance thresholds per business unit and the named model approver", "MAPE, R2, ...; WBD approver for prod", "16, GitHub environment", "Data science"),
    ("18. SageMaker modeling", "Model results in RDS for every registered version or only approved ones", "Every registered version (tagged with the model package ARN)", "13 publisher", "Data science / Backend"),
    # 19. Model refresh and drift (layer 17)
    ("19. Model refresh and drift", "Refresh schedule per business unit and timezone; app-triggered refresh allowed for which roles", "Weekly Monday 06:00 America/New_York; approvers only", "17 Schedules, rule on demand", "Data / Product"),
    ("19. Model refresh and drift", "Drift threshold, check schedule, retrain automatically or alert only", "0.2; daily 07:00; alert only", "17 model monitor, 19", "Data science"),
    # 20. GenAI (layer 18, Release 2)
    ("20. GenAI (Release 2 - not part of R1)", "Written approval for data to external LLM providers; approved providers (or Bedrock-hosted models)", "Approval document before Release 2", "18 GenAI layer", "Responsible AI / Legal"),
    ("20. GenAI (Release 2 - not part of R1)", "Release 1 behaviour of 'invoke explanation tool by default for every run' while GenAI is not part of R1", "Skipped in R1 - the run result shows no explanation", "08 genai_enabled, API", "Product / EY"),
    ("20. GenAI (Release 2 - not part of R1)", "Provider API keys entered in Secrets Manager by WBD", "mmm/<env>/llm/openai, anthropic, google", "08 llm secrets", "Vendor contracts"),
    ("20. GenAI (Release 2 - not part of R1)", "Token quota per business unit and per run; guardrail policy (PII, denied topics, thresholds)", "1,000,000 tokens/day per BU; ~5,000 per run; grounding / relevance 0.75", "08 token quota, 18 Bedrock guardrail", "Responsible AI"),
    # 21. Monitoring, alerting and logging (layer 19)
    ("21. Monitoring and logging", "Alert email lists / paging tool per environment", "mmm-devops@<domain>; prod on-call list", "19 SNS topic - alerts", "Ops"),
    ("21. Monitoring and logging", "Log retention per environment", "30 / 90 / 365 days", "All log groups", "Legal / Audit"),
    ("21. Monitoring and logging", "Splunk shipping required: HEC endpoint, token (entered by WBD), index, source type", "Not required at go-live", "19 Firehose to Splunk (optional), 08 splunk/hec", "Splunk"),
    ("21. Monitoring and logging", "Sensitive data in logs: data identifiers for the CloudWatch Logs data protection policy", "Email, names, AWS keys", "19 Logs data protection policy", "Security / Privacy"),
    ("21. Monitoring and logging", "CloudWatch Application Signals (APM) wanted", "No", "19 Application Signals (optional)", "Ops"),
    # 22. Backup and DR (layer 20)
    ("22. Backup and DR", "RPO / RTO sign-off", "RPO 24 h (RDS PITR 5 min), RTO 4 h", "20", "Ops / Security"),
    ("22. Backup and DR", "Cross-region backup copy (us-west-2) and prod vault lock", "No cross-region copy; vault lock in prod if approved", "20 DR vault (optional), backup vault", "Ops / Security"),
    ("22. Backup and DR", "Restore-test frequency and who signs it off", "Quarterly in staging", "20", "Ops"),
    # 23. Releases, approvals and handover
    ("23. Releases and handover", "Repo admin rights for DevOps (GitHub environments, variables, branch protection)", "Admin role", "GitHub", "GitHub admins"),
    ("23. Releases and handover", "Approvers: staging (EY), prod (WBD), model promotion, Glue script releases", "GitHub users / teams", "GitHub environments", "WBD / EY"),
    ("23. Releases and handover", "CAB change-ticket format and lead time for prod", "CHG1234567; 5 working days", "deploy pipeline", "CAB"),
    ("23. Releases and handover", "Approved security tools (SAST, DAST, GitHub Advanced Security)", "Semgrep / CodeQL / ZAP", "CI", "Security"),
    ("23. Releases and handover", "Proxy CA certificate for the VDI and allow-listed URLs (GitHub, PyPI, npm, Terraform registry, Databricks, LLM providers, Splunk)", ".pem file", "Engineer workstations", "Network"),
    ("23. Releases and handover", "Security incident contact, operations owner after handover, hypercare length", "Names; 4 weeks hypercare", "Runbooks", "Security / Ops"),
]

# (question, proposed default)
DECISIONS = [
    ("Gold -> RDS on slide 1 runs through 'Lambda Functions - Results/data publisher': does Glue write to RDS at all?", "No - Glue export-rds writes Parquet to lakehouse/rds-export/<bu>/<refresh_id>/; the publisher (event reference_data) loads it into RDS through RDS Proxy as mmm_app; Glue has no database access"),
    ("Reference tables too large for a Lambda (15-minute limit)?", "Batched load per table; if one table cannot load within 15 minutes, Glue writes that table directly (only with WBD approval)"),
    ("Publisher reads the Gold Delta tables directly or a Parquet export?", "Parquet export by Glue (plain files are faster and simpler to read in Lambda)"),
    ("Lambdas drawn outside the VPC on slide 2 - inside or outside the VPC?", "Inside the VPC (private subnets) - the publisher must reach RDS Proxy privately; the others for the same egress control"),
    ("What 'lineage' must cover (Glue + Data Catalog, Registry + S3)", "Glue catalog table properties per refresh + SageMaker ML Lineage Tracking (export run -> Glue tables -> training snapshot -> training job -> model package)"),
    ("Lineage UI (Amazon DataZone / SageMaker Catalog)?", "Not in Release 1; optional add-on"),
    ("CloudTrail 'to be enabled across all components'", "WBD org trail (management events) + S3 data events for the MMM data buckets; we verify"),
    ("CloudWatch 'to be enabled across all components'", "Logs, metrics and alarms on every component (ECS, Lambda, Step Functions, Glue, SageMaker, RDS, ALB, WAF, SQS); dashboards per area"),
    ("IAM Identity Center with Okta (slide 2)", "Engineers sign in to AWS through Identity Center federated with Okta; planners only through the Okta OIDC app at the ALB"),
    ("'AWS IAM' on every integration", "One least-privilege IAM role per integration, all under the permission boundary"),
    ("GenAI timing ('Not part of R1')", "Release 2; genai_enabled = false in R1 and the explanation tool is skipped"),
    ("How does data leave Databricks?", "The WBD export job writes Parquet to landing raw/databricks/<bu>/<date>/ through a write-only Unity Catalog role; the Export Trigger Lambda starts and polls it"),
    ("Glue orchestration: Glue workflows / triggers or Step Functions?", "Step Functions (glue:startJobRun.sync per layer) inside model-refresh"),
    ("Lake Formation on the Glue catalog?", "Not used - IAM roles, bucket policies and per-BU KMS keys"),
    ("Silver data-quality failure?", "Stops the refresh and alerts"),
    ("Order of the last refresh steps?", "Publish reference data, train, evaluate, register the model version, record lineage, then write the model results to RDS (rows carry the model package ARN)"),
    ("Optimizer on ECS: one task per run or a worker service?", "One Fargate task per run started by Step Functions (isolation, simple cancel)"),
    ("Concurrency and fairness between business units?", "5 / 20 / 50 runs at a time, bounded by the Fargate quota; first come first served; per-user limits in the app"),
    ("Forecast runs ('upload future titles')?", "Same queue, state machine and optimizer image; run_type forecast"),
    ("User file upload to S3 (slide 2): through the API or straight from the browser?", "Straight from the browser with a presigned URL from the API, scoped to the user's BU prefix; CORS limited to the app domain"),
    ("Malware scanning of uploads?", "Not at go-live; optional GuardDuty Malware Protection for S3"),
    ("Databricks reachability?", "NAT IPs on the workspace IP access list; PrivateLink if WBD requires"),
    ("App reachable from the internet or only WBD ranges? Shield Advanced?", "Internet + WAF + Okta sign-in; no Shield Advanced"),
    ("Database sizes and read replica?", "Single-AZ dev, Multi-AZ staging / prod, no read replica"),
    ("Model drift above the threshold?", "Alert only; daily check switched on after the first approved model"),
    ("Lakehouse in AWS Backup?", "Yes (daily, same retention as RDS); uploads and glue-assets not backed up"),
    ("Shared tooling account / self-hosted runners?", "Not used - GitHub-hosted runners with OIDC"),
    ("Which tool WBD uses to create the resources, and who keeps the state?", "WBD decides; our Terraform can be handed over (state bucket per account, layer 02)"),
]

Q_HEAD = PatternFill("solid", fgColor="1F4E78")
Q_INPUT = PatternFill("solid", fgColor="FFF2CC")


def q_sheet(ws, text, headers, rows, col_widths, input_cols):
    ws.append([text])
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(headers)
    for c in ws[3]:
        c.fill, c.font, c.alignment = Q_HEAD, Font(bold=True, color="FFFFFF"), WRAP
    for r in rows:
        ws.append(list(r))
        for c in ws[ws.max_row]:
            c.alignment, c.border = WRAP, BORDER
            if c.column in input_cols:
                c.fill = Q_INPUT
    widths(ws, col_widths)
    ws.freeze_panes = "A4"
    ws.auto_filter.ref = f"A3:{get_column_letter(len(headers))}{ws.max_row}"


def build_questions():
    wb = Workbook()
    ws = wb.active
    ws.title = "client_inputs"
    q_sheet(ws, "WBD MMM v5 - inputs WBD provides before / while the infra team creates the AWS resources (fill the yellow columns per environment)",
            ["#", "Section", "What WBD provides", "Example / proposed default", "Used for (aws_resource_list_5.xlsx)", "WBD owner",
             "Dev value", "Staging value", "Prod value", "Status", "Notes"],
            [(i, *r, "", "", "", "Open", "") for i, r in enumerate(INPUTS, 1)],
            (5, 26, 60, 44, 30, 22, 22, 22, 22, 10, 30), input_cols=(7, 8, 9, 10, 11))
    q_sheet(wb.create_sheet("decisions_to_confirm"), "WBD MMM v5 - design decisions to confirm (proposed default until WBD answers)",
            ["#", "Question", "Proposed default", "WBD answer", "Status"],
            [(f"Q{i}", *d, "", "Open") for i, d in enumerate(DECISIONS, 1)],
            (6, 60, 70, 40, 10), input_cols=(4, 5))
    wb.save(OUT / "devops_5_client_question.xlsx")


# ------------------------------------------------------------------ design document
def build_docx():
    d = docx.Document()
    d.styles["Normal"].font.name = "Calibri"
    d.styles["Normal"].font.size = Pt(10)

    def p(text, bold_prefix=None):
        para = d.add_paragraph()
        if bold_prefix:
            para.add_run(bold_prefix).bold = True
        para.add_run(text)
        return para

    def bullets(items):
        for it in items:
            d.add_paragraph(it, style="List Bullet")

    def table(headers, rows):
        t = d.add_table(rows=1, cols=len(headers))
        t.style = "Table Grid"
        for i, hd in enumerate(headers):
            t.rows[0].cells[i].text = ""
            t.rows[0].cells[i].paragraphs[0].add_run(hd).bold = True
        for r in rows:
            cells = t.add_row().cells
            for i, v in enumerate(r):
                cells[i].text = str(v)
        d.add_paragraph()

    d.add_heading("WBD MMM - Media Allocation & Measurement Platform", 0).alignment = WD_ALIGN_PARAGRAPH.LEFT
    p("DevOps Implementation Plan v5 - Hybrid Lakehouse + MLOps on AWS (AWS Glue + Data Catalog lineage, SageMaker, ECS Fargate "
      "inference & optimization, Databricks source export, Okta SSO, RDS PostgreSQL, SQS dispatch)").runs[0].bold = True
    note = p("Version 5 of wbd_mmm_ecs_final_4.docx for the client architecture WBD_MMM_Architecture_5.pptx (slide 1: auto ML "
             "activities; slide 2: optimization and explainable planning). v4 is built in the repo (commit e2cac7b); this document "
             "is the v5 plan (13 Nov 2026), not implemented yet. Items marked [ASK] have the proposed default in section 9.")
    note.runs[0].italic = True
    note.runs[0].font.color.rgb = RGBColor(0x59, 0x59, 0x59)

    d.add_heading("1. What changed vs v4")
    p("The two v5 slides keep the v4 layout. The differences are labels, arrows and the security / operations annotations below; "
      "the services are the same, so most of the v4 build stays as it is.")
    table(["#", "Slide", "v4 (built)", "v5", "DevOps impact"], [
        ("1", "1", "Lambda next to Databricks labelled 'Results publisher'", "'Lambda Functions - Export Trigger' (Databricks API connector)", "None - confirms the separate export Lambda built in v4"),
        ("2", "1", "Glue Export Gold -> RDS PostgreSQL (JDBC via RDS Proxy as mmm_etl)", "Glue Export -> 'Lambda Functions - Results/data publisher' -> RDS", "export-rds writes Parquet to S3; publisher event reference_data loads RDS; remove rds/etl, mmm_etl, Glue DB path [ASK]"),
        ("3", "1", "'AWS Glue'; 'SageMaker Registry + S3 - approved models, curves, drift monitoring'", "'AWS Glue + Data Catalog (Lineage)'; Registry + S3 '... + lineage'", "Lineage per refresh: Glue catalog table properties + SageMaker ML Lineage Tracking; RecordLineage state; DataZone optional [ASK]"),
        ("4", "1 + 2", "IAM / KMS only in the security band", "'AWS IAM' on every integration arrow, 'KMS' on every data store", "None - one least-privilege role per integration and CMKs per store already built; documented per resource"),
        ("5", "1 + 2", "Security + Network / Logging bands", "+ box 'Environment level component': Secrets Manager, VPC routes, CloudWatch and CloudTrail 'enabled across all components'", "CloudTrail S3 data events on the MMM buckets (WBD org trail) [ASK]"),
        ("6", "2", "GenAI box (API Gateway, Bedrock Guardrails, OpenAI / Anthropic / Google)", "Same box marked 'Not part of R1'", "Confirms Release 2; enable_genai stays false in R1; explanation tool skipped"),
        ("7", "2", "S3 'store user input files' from the API", "+ arrow 'User file upload to S3' from the UI", "None - browser PUT with a presigned URL is built"),
        ("8", "2", "Okta 'authentication and RBAC'", "+ 'IAM Identity Center' under Okta", "Confirm Okta as the Identity Center identity source (account baseline) [ASK]"),
    ])

    d.add_heading("2. Target platform")
    p("Unchanged from v4: UI + API and the inference & optimization engine on ECS Fargate in three WBD accounts; Okta at the public ALB "
      "behind WAF; RDS PostgreSQL (+ RDS Proxy); SQS -> dispatcher Lambda -> Step Functions -> one ECS optimizer task per run -> S3 "
      "outputs -> results publisher -> RDS; Databricks export (Export Trigger Lambda) -> S3 -> Glue Bronze / Silver / Gold (Delta Lake on "
      "S3) -> training data -> SageMaker train / evaluate / register. New in v5: Gold reference data reaches RDS through the "
      "results/data publisher, and every refresh records lineage.", "Decision: ")

    d.add_heading("3. The two flows")
    d.add_heading("3.1 Auto ML activities (slide 1)", 2)
    bullets([f"{s_id} {name}: {text}" for s_id, slide, name, text in FLOW if slide.startswith("Slide 1")])
    d.add_heading("3.2 Optimization and explainable planning (slide 2)", 2)
    bullets([f"{s_id} {name}: {text}" for s_id, slide, name, text in FLOW if slide.startswith("Slide 2")])
    d.add_heading("3.3 Platform", 2)
    bullets([f"{s_id} {name}: {text}" for s_id, slide, name, text in FLOW if slide.startswith("Platform")])

    d.add_heading("4. Environments")
    table(["Setting", "Dev", "Stage", "Prod"], [
        ("Availability Zones / NAT", "2 / 1", "3 / 3", "3 / 3"),
        ("ECS UI / API tasks", "1-2 / 1-2", "2-3 / 2-4", "2-6 / 3-10"),
        ("Optimizer task", "4 vCPU / 16 GB", "4 vCPU / 16 GB", "8 vCPU / 32 GB"),
        ("max_concurrent_runs / Fargate vCPU quota", "5 / >= 40", "20 / >= 120", "50 / >= 450"),
        ("Glue workers per job", "2 x G.1X", "5 x G.1X", "10 x G.1X"),
        ("RDS PostgreSQL", "db.t4g.medium, single-AZ", "db.r6g.large, Multi-AZ", "db.r6g.xlarge, Multi-AZ"),
        ("Backups (PITR / AWS Backup)", "7 d", "14 d", "35 d + monthly 365 d"),
        ("Log retention", "30 days", "90 days", "365 days"),
        ("GenAI", "Off (Release 2)", "Off (Release 2)", "Off (Release 2)"),
    ])

    d.add_heading("5. Impact on the v4 code")
    table(["Area", "Change", "Why"], CODE_IMPACT)
    p("Removed: " + "; ".join(f"{r[1]}" for r in REMOVED) + ".")
    p("Unchanged: networking, KMS, ECR, ECS ui / api / optimizer, ALB + Okta, WAF, SQS + dispatcher, optimization state machine, "
      "Databricks export Lambda, Glue bronze / silver / gold / export-training / export-monitor, SageMaker training / registry / drift, "
      "GenAI gateway (Release 2), monitoring, backup, CI/CD workflows.")

    d.add_heading("6. Stages (v5 delta)")
    table(["Stage", "v5 change"], [
        ("0-2 Access, questions, design", "Send devops_5_client_question.xlsx; confirm the Gold -> RDS path and lineage scope"),
        ("3-5 Foundation, network, secrets", "Remove rds/etl; Glue connection without data-clients"),
        ("6 Data & storage", "lakehouse prefix rds-export/ (30-day expiry); no mmm_etl"),
        ("9 Optimization engine", "Publisher reference_data event (shared function)"),
        ("10 Data & ML platform", "export-rds to S3; PublishReferenceData + RecordLineage states; refresh role lineage APIs"),
        ("13 Monitoring", "Rows published on the data-pipeline dashboard; publisher failures fail the refresh"),
        ("16 Release 2 GenAI", "Confirmed Release 2 ('Not part of R1')"),
        ("17 Handover", "Runbooks: model-refresh-failed (reference data), rotation (no rds/etl)"),
    ])

    d.add_heading("7. Risks")
    table(["Risk", "Mitigation"], [
        ("Reference tables too large for one Lambda run (15 minutes)", "Batches per table / BU; fallback to the v4 direct Glue write if the volume needs it"),
        ("Lineage gaps when a step is re-run", "Lineage keyed on refresh_id; RecordLineage is idempotent"),
        ("CloudTrail data events cost", "Only the MMM data buckets; write events only in dev"),
    ])

    d.add_heading("8. AWS resource list summary (details in aws_resource_list_5.xlsx)")
    table(["Layer", "Rows", "Release 2", "New in v5", "Changed by v5"], [
        (layer, sum(1 for r in R if r[0] == layer), sum(1 for r in R if r[0] == layer and r[10] == GENAI),
         sum(1 for r in R if r[0] == layer and r[12][0] == NEW), sum(1 for r in R if r[0] == layer and r[12][0] == CHANGED))
        for layer in dict.fromkeys(r[0] for r in R)
    ] + [("Removed vs v4", len(REMOVED), "", "", "")])

    d.add_heading("9. Questions for WBD (v5) and the proposed default")
    table(["#", "Question", "Proposed default"], [(f"Q{i}", *q) for i, q in enumerate(DECISIONS, 1)])
    d.save(OUT / "wbd_mmm_ecs_final_5.docx")


if "--questions-only" in sys.argv:
    build_questions()
else:
    build_resources()
    build_questions()
    build_docx()
print("resource rows:", len(R), "new:", sum(1 for r in R if r[12][0] == NEW), "changed:", sum(1 for r in R if r[12][0] == CHANGED),
      "removed:", len(REMOVED), "| inputs:", len(INPUTS), "decisions:", len(DECISIONS))

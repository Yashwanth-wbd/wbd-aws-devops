"""Builds aws_resource_list_4_new.xlsx and devops_client_question_4_new.xlsx (WBD_MMM_Architecture_4.pptx).

aws_resource_list_4_new.xlsx is the complete AWS resource list written from scratch for the v4 architecture, for the WBD
infrastructure team that creates the resources: every resource with its name per environment, what it does in the v4 flow
(slide 1 auto ML activities, slide 2 optimization and explainable planning, platform), settings and sizes per environment,
dependencies and owner. Names and counts match the Terraform plan of the v4 code (prod, all features on: 547 resources).
devops_client_question_4_new.xlsx is the complete list of inputs and decisions WBD has to provide for v4.

Usage: uv run --no-project --with openpyxl python build_v4_new.py <docs/requirements>
"""
import sys
from pathlib import Path

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
    ("S1-2", "Slide 1 - Auto ML", "Databricks API connector", "Step Functions invokes the Databricks export Lambda. It reads the Databricks service principal from Secrets Manager, gets an OAuth token and starts the export job of the business unit in the WBD Databricks source catalog (Jobs API run-now), then polls it (runs/get)."),
    ("S1-3", "Slide 1 - Auto ML", "Raw data to S3", "The Databricks export job writes 3+ years of history as Parquet to s3://landing/raw/databricks/<bu>/<date>/ through a Unity Catalog external location on a write-only IAM role. The Lambda writes _manifest.json."),
    ("S1-4", "Slide 1 - Auto ML", "AWS Glue - Bronze", "Glue job bronze ingests the raw Parquet into Bronze Delta tables (lakehouse bucket, Glue Data Catalog database bronze)."),
    ("S1-5", "Slide 1 - Auto ML", "AWS Glue - Silver", "Glue job silver cleanses and validates the data (Glue Data Quality ruleset); a failed rule stops the refresh and alerts."),
    ("S1-6", "Slide 1 - Auto ML", "AWS Glue - Gold", "Glue job gold builds the per-business-unit modeling tables (adstock, saturation) - Delta Lake storage on S3."),
    ("S1-7", "Slide 1 - Auto ML", "Glue exports", "export-training writes an immutable Parquet snapshot to the training-data bucket (Object Lock); export-rds writes Gold reference tables to RDS PostgreSQL through RDS Proxy."),
    ("S1-8", "Slide 1 - Auto ML", "SageMaker training (in the VPC)", "SageMaker training job (multi-stage model) reads the training data and writes the model artifact to the models bucket."),
    ("S1-9", "Slide 1 - Auto ML", "SageMaker evaluation", "SageMaker processing job evaluates the model: baseline -> channel lift -> title adjustment; writes evaluation, predictions, lift and response curves."),
    ("S1-10", "Slide 1 - Auto ML", "Model registration", "The model version is registered in the SageMaker Model Registry (group per business unit, PendingManualApproval). A named WBD approver approves it; approved curves are published to the models bucket."),
    ("S1-11", "Slide 1 - Auto ML", "Results written to RDS", "The results publisher Lambda writes the model predictions, lift and evaluation results to RDS PostgreSQL."),
    ("S1-12", "Slide 1 - Auto ML", "Model drift monitoring", "Daily schedule per business unit starts model-monitor: Databricks export + Glue layers + export-monitor -> SageMaker drift job -> ModelDrift metric and alarm (optional automatic refresh)."),
    ("S2-1", "Slide 2 - Optimization", "Sign-in", "Planner opens the app: Route 53 / WBD DNS -> AWS WAF -> public Application Load Balancer (HTTPS, ACM certificate) -> Okta sign-in at the ALB (authentication, groups for RBAC)."),
    ("S2-2", "Slide 2 - Optimization", "UI and API on ECS", "ECS Fargate service ui (React + TypeScript, QA dashboard) and service api (Python FastAPI + LangGraph tools) in private subnets; API reads / writes plans, runs and allocations in RDS PostgreSQL through RDS Proxy."),
    ("S2-3", "Slide 2 - Optimization", "Upload inventory / future titles", "The API returns a presigned URL; the browser uploads the input file straight to the S3 uploads bucket (user input files)."),
    ("S2-4", "Slide 2 - Optimization", "Queue the run", "The API stores the run as QUEUED and sends a message to the SQS queue optimization-requests (dead-letter queue after 10 failures)."),
    ("S2-5", "Slide 2 - Optimization", "Message dispatcher", "The dispatcher Lambda reads the queue and starts a Step Functions optimization execution while fewer than max_concurrent_runs are running."),
    ("S2-6", "Slide 2 - Optimization", "ECS inference & optimization", "Step Functions runs one ECS Fargate optimizer task per run (Model Summarizer -> Optimizer -> Simulation). It reads the input file, the approved model (Model Registry) and the approved response curves (S3)."),
    ("S2-7", "Slide 2 - Optimization", "S3 outputs", "The optimizer writes the full run evidence to the results bucket (runs/<run_id>/output)."),
    ("S2-8", "Slide 2 - Optimization", "Results publisher", "Step Functions invokes the results publisher Lambda, which writes plans, runs and allocations to RDS PostgreSQL. The UI shows the result."),
    ("S2-9", "Slide 2 - Optimization", "Explanation (GenAI)", "The API's LangGraph explanation tool calls the private API Gateway LLM gateway -> proxy Lambda -> Amazon Bedrock Guardrails -> OpenAI / Anthropic / Google models."),
    ("S2-10", "Slide 2 - Optimization", "Approve / export", "Approved scenarios are stored immutably in the approved-worm bucket (Object Lock); Excel exports go to the exports bucket (30-day expiry)."),
    ("P-1", "Platform", "Security", "Accounts, IAM roles, KMS keys, Secrets Manager / Parameter Store, security groups, VPC endpoints - used by every step above."),
    ("P-2", "Platform", "Logging / Operations", "CloudWatch logs, metrics, alarms, dashboards, EventBridge alert rules, SNS alerts, CloudTrail, optional shipping to Splunk."),
    ("P-3", "Platform", "CI/CD", "GitHub Actions log in through OIDC roles, push images to ECR, run Terraform plan / apply, deploy ECS services, approve models."),
    ("P-4", "Platform", "Backup / DR / cost", "AWS Backup (RDS and buckets), RDS point-in-time restore, optional cross-region copy, budgets and cost anomaly alerts."),
]

# (layer, AWS service, resource, name (use {e} for dev / stg / prd), quantity per env, flow step, what it does in the v4
#  flow, key configuration, (dev, staging, prod) setting, depends on, scope, owner)
R = []


def add(layer, service, resource, name, qty, flow, what, config, per_env, depends, scope, owner):
    R.append((layer, service, resource, name, qty, flow, what, config, per_env, depends, scope, owner))


L = "01. Account baseline"
add(L, "AWS Organizations", "AWS account per environment", "wbd-mmm-dev / wbd-mmm-stage / wbd-mmm-prod", ALL1, "P-1",
    "Separate WBD-owned account per environment; every resource below is created in each account.", "Member of the WBD organization; budget owner per account",
    s("Dev", "Staging", "Prod"), "-", BASE, PLAT)
add(L, "AWS Organizations", "Service Control Policies", "WBD standard SCPs", ALL1, "P-1",
    "Region lock and guardrails. Must allow us-east-1 (+ us-west-2 for DR) and the services of this list (ECS, Lambda, Step Functions, Glue, SageMaker, Bedrock, API Gateway, Firehose).",
    "Allow-list of the services above", s("same"), "AWS account", BASE, PLAT)
add(L, "IAM Identity Center", "Permission sets", "ReadOnly, Developer, DevOps, Security, BreakGlass", s("5"), "P-1",
    "SSO access for engineers through Okta groups; no IAM users. BreakGlass use raises an alert (rule breakglass-used).", "Prod: DevOps time-limited elevation",
    s("DevOps + ReadOnly", "DevOps + ReadOnly", "ReadOnly; DevOps on approval"), "Okta groups", BASE, PLAT)
add(L, "CloudTrail", "Organization trail", "WBD org trail", ALL1, "P-2",
    "Audit of every API call; management events must reach EventBridge in the account (break-glass alert).", "Multi-region, log file validation", s("same"), "-", BASE, PLAT)
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
    ("data-clients", "Everything that talks to the database (api, migrate, publisher, Glue)", "Out 5432 to RDS Proxy SG; out 443 to endpoints / S3", "S1-7, S2-2, S2-8", CORE),
    ("rds-proxy", "RDS Proxy", "In 5432 from data-clients SG; out 5432 to RDS SG", "S2-2", CORE),
    ("rds", "RDS PostgreSQL", "In 5432 from RDS Proxy SG only", "S2-2", CORE),
    ("endpoints", "Interface VPC endpoints", "In 443 from the VPC CIDR", "P-1", CORE),
    ("sagemaker", "SageMaker training / processing jobs", "Self-referencing (distributed training); out 443 to endpoints and S3", "S1-8, S1-9, S1-12", DP),
    ("glue", "Glue job ENIs", "Self-referencing all traffic (Spark driver <-> executors); out 443 to endpoints and S3", "S1-4..S1-7", DP),
    ("databricks-export", "Databricks export Lambda", "No inbound; out 443 to the Databricks workspace (NAT or PrivateLink) and endpoints", "S1-2", DP),
    ("genai", "LLM proxy Lambda", "No inbound; out 443 to the approved LLM providers and endpoints", "S2-9", GENAI),
):
    add(L, "VPC", f"Security group - {sg}", "mmm-{e}-" + sg + "-sg", ALL1, flow, what + ".", rules, s("same"), "VPC", scope, INFRA)

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
    ("rds/migrate", "DB user of the migrate task (schema owner)", "P-3", CORE, "Value set by the DB bootstrap"),
    ("rds/proxy", "DB user list for RDS Proxy authentication", "S2-2", CORE, "Value set by the DB bootstrap"),
    ("rds/etl", "DB user mmm_etl of the Glue export-rds job", "S1-7", DP, "Value set by the DB bootstrap"),
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
add(L, "S3", "S3 bucket - lakehouse (Delta Lake)", "wbd-mmm-{e}-lakehouse-use1", ALL1, "S1-4..S1-6, S1-12",
    "Bronze / Silver / Gold Delta tables written by Glue; monitoring/<bu>/<date>/ features for the drift check.", BUCKET_STD + "; per-BU KMS; monitoring/ expires after 90 d",
    s("same"), "KMS BU keys", DP, INFRA)
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
add(L, "RDS", "RDS for PostgreSQL instance", "mmm-{e}-postgres", ALL1, "S1-7, S1-11, S2-2, S2-8",
    "System of record: plans, runs, allocations, audit, Gold reference tables (Glue export-rds), model predictions / lift / evaluation (publisher). Row-level security per BU.",
    "PostgreSQL 16.6, gp3, KMS rds, Performance Insights, Enhanced Monitoring, IAM auth, logs postgresql + upgrade to CloudWatch, deletion protection (prod)",
    s("db.t4g.medium, single-AZ, 50 GB (max 200), backup 7 d", "db.r6g.large, Multi-AZ, 100 GB (max 500), backup 14 d", "db.r6g.xlarge, Multi-AZ, 200 GB (max 1000), backup 35 d"),
    "Subnet group, SG rds, KMS rds", CORE, INFRA)
add(L, "IAM", "IAM role - RDS Enhanced Monitoring", "mmm-{e}-postgres-monitoring", ALL1, "P-2", "OS metrics of the DB instance.", "AmazonRDSEnhancedMonitoringRole", s("same"), "-", CORE, INFRA)
add(L, "RDS", "RDS Proxy + target group + target", "mmm-{e}-postgres-proxy", s("3"), "S1-7, S2-2, S2-8",
    "Connection pooling for the API tasks, publisher Lambda and Glue jobs; TLS required; IAM auth.", "Secrets api/db, rds/migrate, rds/etl, rds/proxy; data subnets; SG rds-proxy", s("same"), "RDS, secrets", CORE, INFRA)
add(L, "IAM", "IAM role - RDS Proxy", "mmm-{e}-postgres-proxy", ALL1, "S2-2", "Lets RDS Proxy read the DB user secrets.", "secretsmanager:GetSecretValue + kms:Decrypt", s("same"), "Secrets", CORE, INFRA)
add(L, "CloudWatch Logs", "Log groups - RDS", "/aws/rds/instance/mmm-{e}-postgres/postgresql ; /upgrade", s("2"), "P-2", "Database and upgrade logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)
add(L, "PostgreSQL", "DB users and schema (inside the database)", "mmm_app, mmm_migrate, mmm_etl", s("3"), "S1-7, S2-2", "Least-privilege users per writer; tables from the backend migrations.",
    "Created by the DB bootstrap + migrate task", s("same"), "RDS", CORE, APPT)

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
         "migrate": "Migrate permissions: rds-db:connect as mmm_migrate",
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
add(L, "Lambda", "Lambda - results publisher (+ alias live)", "mmm-{e}-results-publisher", s("2"), "S1-11, S2-8",
    "Writes plans, runs and allocations (optimization) and model predictions, lift and evaluation (refresh) from S3 to RDS PostgreSQL.",
    "Python 3.12, 512 MB, 120 s, reserved concurrency 10, VPC (SG lambda + data-clients), X-Ray", s("same"), "RDS Proxy, results / models bucket", CORE, INFRA_PIPE)
add(L, "IAM", "IAM role - results publisher", "mmm-{e}-results-publisher-lambda", ALL1, "S1-11, S2-8", "rds-db:connect via Proxy, read results/runs/* and models/evaluation/*, logs.", "Permission boundary", s("same"), "-", CORE, INFRA)
add(L, "CloudWatch Logs", "Log group - results publisher", "/aws/lambda/mmm-{e}-results-publisher", ALL1, "P-2", "Publisher logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", CORE, INFRA)

L = "14. Databricks export (slide 1)"
add(L, "IAM", "IAM role - Databricks Unity Catalog (write-only)", "mmm-{e}-databricks-uc", ALL1, "S1-3",
    "Storage credential for the Databricks export job: write only to landing raw/databricks/* with the BU keys.", "Trust: Databricks UC master role + external id", s("same"), "landing bucket, BU keys", DP, INFRA)
add(L, "Lambda", "Lambda - Databricks export (API connector)", "mmm-{e}-databricks-export", ALL1, "S1-2, S1-3",
    "start: OAuth M2M token -> Jobs API run-now (target URI per BU); status: runs/get; writes _manifest.json.",
    "Python 3.12, 256 MB, 60 s, VPC (SG databricks-export), egress via NAT or PrivateLink, X-Ray", s("same"), "Secret databricks/export-sp, SSM job ids", DP, INFRA_PIPE)
add(L, "IAM", "IAM role - Databricks export Lambda", "mmm-{e}-databricks-export-lambda", ALL1, "S1-2", "Read databricks/export-sp + SSM databricks/*, put _manifest.json under landing raw/databricks/, BU keys.", "Permission boundary", s("same"), "-", DP, INFRA)
add(L, "CloudWatch Logs", "Log group - Databricks export", "/aws/lambda/mmm-{e}-databricks-export", ALL1, "P-2", "Export Lambda logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "Databricks", "Databricks export job per business unit", "WBD workspace", s("3"), "S1-2, S1-3", "Exports the source tables as Parquet to the output URI it is given (params business_unit, output_uri, purpose, request_id).",
    "Job id per BU -> SSM databricks/export_job_ids", s("same"), "UC external location", DP, DBX)
add(L, "Databricks", "Service principal (export) + Unity Catalog storage credential + external location", "WBD workspace", s("3"), "S1-2, S1-3",
    "Service principal with 'Can manage run' on the export jobs; external location on s3://landing/raw/databricks/ using role mmm-{e}-databricks-uc.", "Workspace IP access list allows our NAT IPs (or PrivateLink)",
    s("same"), "IAM role databricks-uc", DP, DBX)

L = "15. AWS Glue lakehouse (slide 1)"
add(L, "Glue", "Glue Data Catalog databases - bronze, silver, gold", "mmm_{e}_bronze / mmm_{e}_silver / mmm_{e}_gold", s("3"), "S1-4..S1-6", "Catalog of the Delta tables in the lakehouse bucket.", "Location s3://lakehouse/<layer>/", s("same"), "lakehouse bucket", DP, INFRA)
add(L, "Glue", "Glue Data Catalog encryption settings", "account / region setting", ALL1, "S1-4..S1-6", "Encrypts catalog metadata and connection passwords (s3 key). Skip if WBD already manages it.", "SSE-KMS", s("same"), "KMS s3", DP, INFRA)
add(L, "Glue", "Glue security configuration", "mmm-{e}-glue", ALL1, "S1-4..S1-7", "KMS for job S3 output, bookmarks and CloudWatch logs.", "S3 s3 key, logs key", s("same"), "KMS", DP, INFRA)
add(L, "Glue", "Glue connection (NETWORK)", "mmm-{e}-glue-vpc", ALL1, "S1-4..S1-7", "Runs every job in a private app subnet; export-rds reaches RDS Proxy as mmm_etl.", "SG glue + data-clients", s("same"), "App subnet, SGs", DP, INFRA)
add(L, "IAM", "IAM role - Glue jobs", "mmm-{e}-glue", ALL1, "S1-4..S1-7",
    "Read landing raw/databricks/*, read / write lakehouse, write training-data, read scripts + write temp in glue-assets, catalog, DQ, rds-db:connect as mmm_etl, BU keys, logs, metrics.", "Permission boundary", s("same"), "-", DP, INFRA)
add(L, "CloudWatch Logs", "Log group - Glue jobs", "/aws-glue/jobs/mmm-{e}", ALL1, "P-2", "Continuous logging of every Glue job.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "Glue", "Glue Data Quality ruleset - silver", "mmm-{e}-silver", ALL1, "S1-5", "Rules evaluated in the silver job; a failure stops the refresh and alerts.", "DQDL rules from the data engineers", s("same"), "Catalog silver", DP, INFRA)
for job, what, flow in (
    ("bronze", "Raw Databricks Parquet -> Bronze Delta tables (job bookmarks)", "S1-4"),
    ("silver", "Cleanse, conform and validate (Data Quality) -> Silver", "S1-5"),
    ("gold", "Per-BU modeling tables (adstock, saturation) -> Gold", "S1-6"),
    ("export-training", "Gold -> immutable Parquet + metadata.json in training-data/<bu>/<refresh_id>/", "S1-7"),
    ("export-rds", "Gold reference tables -> RDS PostgreSQL through RDS Proxy (mmm_etl, IAM token)", "S1-7"),
    ("export-monitor", "Latest features -> lakehouse/monitoring/<bu>/<date>/ for the drift check", "S1-12"),
):
    add(L, "Glue", f"Glue job - {job}", "mmm-{e}-glue-" + job, ALL1, flow, what + ".",
        "Glue 5.0 Spark, --datalake-formats delta, connection glue-vpc, security config, timeout 120 min, script s3://glue-assets/scripts/" + job + ".py",
        s("G.1X x 2 workers", "G.1X x 5 workers", "G.1X x 10 workers"), "Role, connection, glue-assets", DP, INFRA_PIPE)

L = "16. SageMaker modeling (slide 1)"
add(L, "IAM", "IAM role - SageMaker training / evaluation / drift", "mmm-{e}-sagemaker-training", ALL1, "S1-8..S1-12", "Read training-data and lakehouse/monitoring, write models, register model packages, VPC ENIs, logs, metrics.", "Permission boundary", s("same"), "-", DP, INFRA)
add(L, "SageMaker", "Model package groups - one per business unit", "mmm-{e}-streaming / -theatrical / -usnetworks", s("3"), "S1-10, S2-6", "Model Registry: every trained version (PendingManualApproval -> Approved); the optimizer reads the approved one.", "-", s("same"), "-", DP, INFRA)
add(L, "CloudWatch Logs", "Log groups - SageMaker TrainingJobs, ProcessingJobs", "/aws/sagemaker/TrainingJobs ; /aws/sagemaker/ProcessingJobs", s("2"), "P-2", "Training, evaluation and drift job logs.", "KMS logs", s("30 d", "90 d", "365 d"), "KMS logs", DP, INFRA)
add(L, "SageMaker", "Training job (per refresh)", "mmm-{e}-train-<bu>-<id>", s("per refresh"), "S1-8", "Trains the multi-stage model in the VPC; writes the artifact and drift baseline.", "VPC app subnets, SG sagemaker, KMS sagemaker",
    s("ml.m5.2xlarge"), "Training image, role", RUN, DS)
add(L, "SageMaker", "Processing job - evaluation (per refresh)", "mmm-{e}-eval-<bu>-<id>", s("per refresh"), "S1-9", "Baseline -> channel lift -> title adjustment; evaluation.json, curves, predictions, lift.", "VPC, KMS sagemaker",
    s("ml.m5.xlarge"), "Training image, role", RUN, DS)
add(L, "SageMaker", "Processing job - drift (per check)", "mmm-{e}-drift-<bu>-<id>", s("daily per BU"), "S1-12", "Compares the latest features with the baseline; ModelDrift metric.", "VPC, KMS sagemaker", s("ml.m5.xlarge"), "Training image, role", RUN, DS)

L = "17. Model refresh and drift orchestration (slide 1)"
add(L, "Step Functions", "State machine - model refresh", "mmm-{e}-model-refresh", ALL1, "S1-1..S1-11",
    "Databricks export (Lambda start / status) -> Glue bronze -> silver -> gold -> export-training + export-rds -> train -> evaluate -> register -> publish model results to RDS.",
    "Standard, logging ALL, X-Ray", s("same"), "Lambdas, Glue jobs, SageMaker role", DP, INFRA)
add(L, "IAM", "IAM role - model refresh state machine", "mmm-{e}-model-refresh-sfn", ALL1, "S1-1..S1-11", "Invoke export + publisher Lambdas, glue:StartJobRun / GetJobRun, SageMaker jobs + registry, PassRole, logs.", "Permission boundary", s("same"), "-", DP, INFRA)
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
    "Single entry from the API's LangGraph explanation tool to the LLM providers.", "Private endpoint (execute-api VPC endpoint), IAM auth, stage throttling, access logs", s("same"), "execute-api endpoint", GENAI, INFRA)
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
add(L, "CloudWatch", "CloudWatch alarms (data platform)", "see sheet alarms_and_events", s("8"), "P-2", "Refresh / monitor failures, refresh overdue, model drift per BU, Databricks export errors.", "Actions to SNS alerts", s("same"), "SNS", DP, INFRA)
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
    ("Backend team", "DB migrations (tables, row-level security), DB users mmm_app / mmm_migrate / mmm_etl", "Run by the migrate task", "Before the API goes live"),
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


LEGEND = ("Use the filter on 'Release' (Release 1 = go-live incl. the slide 1 model refresh; Release 2 = GenAI explanation) "
          "and on 'Scope' (required, data platform, GenAI, optional, account baseline, quota, run time).")


def build_resources():
    wb = Workbook()
    ws = wb.active
    ws.title = "README"
    title(ws, "WBD MMM v4 - complete AWS resource list for the WBD infrastructure team",
          "Source: WBD_MMM_Architecture_4.pptx (slide 1 auto ML activities, slide 2 optimization and explainable planning). "
          "Names and counts match the Terraform code of the v4 build (12 Nov 2026).")
    for k, v in (
        ("Purpose", "The WBD infrastructure team creates the AWS resources of the MMM platform from this list, in the order of the layers."),
        ("Environments", "Three WBD-owned AWS accounts: dev, staging, prod. Region us-east-1 (DR us-west-2, only if approved)."),
        ("Naming", "Resources: mmm-<env>-<purpose> with <env> = dev / stg / prd. Buckets: wbd-mmm-<env>-<purpose>-use1. "
                   "Secrets: mmm/<env>/<path>. SSM parameters: /mmm/<env>/<path>. KMS aliases: alias/mmm-<env>-<purpose>. Glue databases: mmm_<env>_<layer>."),
        ("Tags (every resource)", "Project = wbd-mmm, Environment = dev / staging / prod, Owner = <WBD team>, CostCenter = <WBD value>, ManagedBy = <tool>; backup = true on RDS and the backed-up buckets."),
        ("Business units", BUS + " (resources marked 'per BU' exist once per business unit)."),
        ("Sheets", "all_resources = complete list with dev / staging / prod values; dev, staging, prod = the same list with the real names of that environment; "
                   "architecture_flow = the v4 flow steps referenced in column 'Flow step'; alarms_and_events = every alarm and alert rule; "
                   "outside_aws = what other WBD teams provide; summary = count per layer."),
        ("Release column", "Release 1 = everything needed for go-live (slide 2 optimization + slide 1 auto ML + platform); "
                           "Release 2 = GenAI explanation (API Gateway LLM gateway, Bedrock Guardrails, LLM secrets). Filter on it."),
        ("Scope column", f"'{CORE}' = needed for go-live; '{DP}' = slide 1 auto ML (can be created after the core); '{GENAI}'; '{OPT}'; "
                         f"'{BASE}' = should already exist in a WBD account; '{QUOTA}'; '{RUN}' = listed so the flow is complete, not created by the infra team."),
        ("Owner column", "Who creates it. 'first version; new revisions by the deploy pipeline' = the infra team creates the resource once, "
                         "the CI/CD pipeline then deploys new code / task revisions (needs the GitHub roles of layer 04)."),
        ("Secrets", "Secret values are never in this file or in Git; the owner enters them in Secrets Manager. Placeholders are marked '# add actual value'."),
        ("Legend", LEGEND),
    ):
        ws.append([k, v])
        style_body(ws)
        ws.cell(ws.max_row, 1).font = Font(bold=True)
    widths(ws, (22, 140))

    headers = ["#", "Release", "Layer", "AWS service", "Resource", "Name", "Qty", "Flow step", "What it does in the v4 flow",
               "Key configuration", "Dev", "Staging", "Prod", "Depends on", "Scope", "Created by / owner"]
    ws = wb.create_sheet("all_resources")
    title(ws, "All AWS resources - v4 architecture (dev / staging / prod)",
          "<env> in names = dev / stg / prd. Qty = count in one environment (dev / staging / prod when different). " + LEGEND)
    ws.append(headers)
    style_header(ws, 4)
    for i, (layer, svc, res, name, qty, flow, what, cfg, per_env, dep, scope, owner) in enumerate(R, 1):
        ws.append([i, release(scope), layer, svc, res, generic(name), joined(qty), flow, what, cfg, *per_env, dep, scope, owner])
        style_body(ws)
    widths(ws, (5, 11, 22, 16, 34, 38, 9, 12, 60, 46, 20, 20, 22, 22, 24, 24))
    ws.freeze_panes = "F5"
    ws.auto_filter.ref = f"A4:{get_column_letter(len(headers))}{ws.max_row}"

    for env, short, label in ENVS:
        ws = wb.create_sheet(env)
        title(ws, f"{label} - AWS resources to create (v4 architecture)",
              f"Real names for {label} (<env> = {short}). Setting = the {label} value. " + LEGEND)
        ws.append(["#", "Release", "Layer", "AWS service", "Resource", f"Name ({label})", "Qty", "Flow step", "What it does in the v4 flow",
                   "Key configuration", f"{label} setting", "Depends on", "Scope", "Created by / owner", "Created (Y/N)", "ARN / ID", "Notes"])
        style_header(ws, 4)
        idx = ("dev", "staging", "prod").index(env)
        for i, (layer, svc, res, name, qty, flow, what, cfg, per_env, dep, scope, owner) in enumerate(R, 1):
            ws.append([i, release(scope), layer, svc, res, name.replace("{e}", short), qty[idx], flow, what, cfg, per_env[idx], dep, scope, owner,
                       "", "", ""])
            style_body(ws)
        widths(ws, (5, 11, 22, 16, 34, 40, 9, 12, 60, 46, 24, 22, 24, 24, 10, 30, 24))
        ws.freeze_panes = "F5"
        ws.auto_filter.ref = f"A4:Q{ws.max_row}"

    ws = wb.create_sheet("architecture_flow")
    title(ws, "v4 architecture flow - steps referenced in the resource list",
          "Slide 1 = auto ML activities (model refresh); slide 2 = optimization and explainable planning; Platform = cross-cutting bands.")
    ws.append(["Step", "Slide", "Step name", "What happens", "Resources used (rows on all_resources)"])
    style_header(ws, 4)
    for step, slide, name, text in FLOW:
        used = [str(i) for i, r in enumerate(R, 1) if step in flow_steps(r[5])]
        ws.append([step, slide, name, text, ", ".join(used)])
        style_body(ws)
    widths(ws, (8, 22, 28, 100, 40))
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A4:E{ws.max_row}"

    ws = wb.create_sheet("alarms_and_events")
    title(ws, "CloudWatch alarms and EventBridge alert rules (all go to SNS mmm-<env>-alerts)",
          "Thresholds are the defaults of the code; dev / staging / prod use the same rules.")
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

    ws = wb.create_sheet("summary")
    title(ws, "Resource count per layer", "Rows of all_resources per layer and scope. AWS objects = sum of Qty in prod "
          "(without account baseline, quotas and run-time objects; settings such as lifecycle or bucket policy are part of their resource).")
    scopes = (CORE, DP, GENAI, OPT, BASE, QUOTA, RUN)
    ws.append(["Layer", "Rows", "Release 1", "Release 2", *scopes, "AWS objects (prod)"])
    style_header(ws, 4)

    def line(label, rows):
        ws.append([label, len(rows), *(sum(1 for r in rows if release(r[10]) == rel) for rel in ("Release 1", "Release 2")),
                   *(sum(1 for r in rows if r[10] == sc) for sc in scopes), objects(rows)])
        style_body(ws)

    for layer in dict.fromkeys(r[0] for r in R):
        line(layer, [r for r in R if r[0] == layer])
    line("Total", R)
    for c in ws[ws.max_row]:
        c.font = Font(bold=True)
    widths(ws, (40, 8, 10, 10, 16, 22, 22, 18, 18, 12, 18, 16))

    wb.save(OUT / "aws_resource_list_4_new.xlsx")


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
# (section, what WBD provides, example / default, used for (resource / setting), WBD owner)
INPUTS = [
    ("1. Provisioning model", "Who creates the AWS resources: WBD Infra with their own tooling (CloudFormation / Terraform / console) or WBD runs our Terraform", "WBD Infra creates them from aws_resource_list_4_new.xlsx", "All layers", "Cloud Platform / Infra"),
    ("1. Provisioning model", "How we receive the created resource ARNs / IDs back (needed for app config and GitHub variables)", "Filled 'ARN / ID' column of the env sheets, or SSM / Terraform outputs", "All layers", "Infra"),
    ("1. Provisioning model", "Naming and tagging standard: accept mmm-<env>-* / wbd-mmm-<env>-*-use1 and the tags in the README, or give the WBD standard", "Project, Environment, Owner, CostCenter, ManagedBy", "All resources", "Cloud Platform"),
    ("1. Provisioning model", "IAM roles: does WBD create the application roles with our policies, and is a WBD permission boundary mandatory", "WBD creates them with mmm-<env>-permission-boundary", "Layer 04 + every IAM role", "Security / Infra"),
    ("1. Provisioning model", "May the deploy pipeline (GitHub OIDC roles) update ECS services, task definitions, Lambda code and Glue scripts after the first creation", "Yes - roles gha-deploy / gha-ecr-push", "Layer 04, 11, 13-15", "Security / Cloud Platform"),
    ("1. Provisioning model", "Timeline and change process for creating the resources per environment (dev first)", "Change ticket per environment", "-", "Infra / CAB"),
    ("2. AWS accounts and access", "AWS account IDs (dev, staging, prod)", "12 digits", "Layer 01", "Cloud Platform"),
    ("2. AWS accounts and access", "Approved primary and DR region (Glue, SageMaker, Bedrock must be available)", "us-east-1, us-west-2", "Layer 01, 20", "Cloud Platform"),
    ("2. AWS accounts and access", "SCPs allow the services of the list (ECS, Lambda, Step Functions, Glue, SageMaker, Bedrock, API Gateway, Firehose, Backup)", "Confirmation", "Layer 01", "Cloud Platform"),
    ("2. AWS accounts and access", "IAM Identity Center start URL, permission sets and Okta groups for DevOps", "DevOps (dev, staging), ReadOnly (all), prod time-limited elevation", "Layer 01", "Identity / Cloud Platform"),
    ("2. AWS accounts and access", "Confirm the account baseline is on: CloudTrail org trail (events to EventBridge), GuardDuty, Security Hub, Config, Inspector, Access Analyzer, S3 Block Public Access, EBS encryption", "Confirmation", "Layer 01", "Security"),
    ("2. AWS accounts and access", "Service quota increases: Fargate On-Demand vCPU, Glue concurrent runs / DPUs, SageMaker training and processing instances", "Fargate 40 / 120 / 450 vCPU; Glue >= 20 runs; SageMaker >= 3 each", "Layer 01", "Cloud Platform"),
    ("3. Network", "VPC CIDR per environment (no overlap with WBD)", "10.40.0.0/19, 10.40.32.0/19, 10.40.64.0/19", "Layer 05", "Network"),
    ("3. Network", "Availability Zones", "2 in dev, 3 in staging / prod (use1-az1, az2, az4)", "Layer 05", "Network"),
    ("3. Network", "NAT gateways allowed for egress, or a central firewall / proxy (Databricks API, Okta, LLM providers)", "NAT: 1 in dev, 1 per AZ in staging / prod", "Layer 05", "Network"),
    ("3. Network", "Connect to the WBD network: Transit Gateway ID and routes; DNS forwarding domains and resolver IPs", "Not required unless VDI / Splunk / on-prem access is needed", "Layer 05 (optional)", "Network"),
    ("3. Network", "Who may reach the app: internet or only WBD IP ranges", "Internet + WAF + Okta sign-in", "Layer 06 SG alb, layer 12", "Security / Network"),
    ("3. Network", "Proxy CA certificate for the VDI and allow-listed URLs (GitHub, PyPI, npm, Terraform registry, Databricks, LLM providers, Splunk)", ".pem file", "Engineer workstations", "Network"),
    ("4. Domain, certificate and sign-in", "App domain name per environment (also the only CORS origin of the uploads bucket)", "mmm-dev.<domain>, mmm-stg.<domain>, mmm.<domain>", "Layer 09 uploads, layer 12", "DNS"),
    ("4. Domain, certificate and sign-in", "ACM certificate in us-east-1 and the DNS record to the ALB (WBD DNS or a Route 53 zone we may use)", "arn:aws:acm:...; CNAME", "Layer 12", "DNS / PKI"),
    ("4. Domain, certificate and sign-in", "Okta OIDC web app per environment: issuer URL and client ID (redirect https://<app>/oauth2/idpresponse)", "https://wbd.okta.com/oauth2/default, 0oa...", "Layer 08 /okta/issuer, layer 12", "Identity"),
    ("4. Domain, certificate and sign-in", "Okta client secret entered in Secrets Manager by WBD (never by email)", "mmm/<env>/okta/alb-client", "Layer 08", "Identity"),
    ("4. Domain, certificate and sign-in", "Okta group names for business unit and role (groups claim in the ID token)", "mmm-bu-streaming, mmm-role-planner", "Layer 12, API RBAC", "Identity"),
    ("4. Domain, certificate and sign-in", "Session length; MFA / step-up for approvals", "12 hours", "Layer 12", "Identity"),
    ("4. Domain, certificate and sign-in", "WAF policy: rate limit, country allow-list, Shield Advanced", "2000 requests / 5 min per IP; no geo block; no Shield Advanced", "Layer 12", "Security"),
    ("5. Database", "RDS PostgreSQL size per environment (instance, storage, Multi-AZ, read replica)", "dev db.t4g.medium single-AZ 50 GB; staging db.r6g.large Multi-AZ 100 GB; prod db.r6g.xlarge Multi-AZ 200 GB; no replica", "Layer 10", "Architecture / Ops"),
    ("5. Database", "Backup retention and maintenance windows", "PITR 7 / 14 / 35 days; Sunday maintenance", "Layer 10, 20", "Ops"),
    ("5. Database", "Who creates the DB users (mmm_app, mmm_migrate, mmm_etl) and enters their secrets", "DevOps DB bootstrap after the instance exists", "Layer 08, 10", "Infra / DevOps"),
    ("6. Optimization (slide 2)", "Optimizer task size and maximum run time", "4 vCPU / 16 GB / 50 GiB (prod 8 vCPU / 32 GB); 60 minutes", "Layer 13", "Data science"),
    ("6. Optimization (slide 2)", "Runs allowed at the same time and maximum queue wait", "5 / 20 / 50 runs; 30 minutes", "Layer 08 max_concurrent_runs, layer 13", "Business / EY"),
    ("6. Optimization (slide 2)", "API / UI task counts per environment", "api 1-2 / 2-4 / 3-10, ui 1-2 / 2-3 / 2-6", "Layer 11", "Architecture"),
    ("6. Optimization (slide 2)", "Accepted upload file types, maximum file size, retention of uploads", "xlsx / csv, 50 MB, 90 days", "Layer 09 uploads", "Product / Legal"),
    ("6. Optimization (slide 2)", "Malware scanning of uploads required (GuardDuty Malware Protection for S3)", "No", "Layer 09 (optional)", "Security"),
    ("6. Optimization (slide 2)", "'Upload future titles' file format and use", "Template xlsx; run type forecast", "API contract", "Product / Data science"),
    ("7. Databricks export (slide 1)", "Databricks workspace URL and account ID", "https://dbc-....cloud.databricks.com", "Layer 08 /databricks/host", "Databricks"),
    ("7. Databricks export (slide 1)", "Source catalog / schema / tables per business unit (3+ years), size and growth", "wbd_prod.mmm.<table>; GB per BU", "Glue sizing", "Databricks / Data owners"),
    ("7. Databricks export (slide 1)", "Export job ID per business unit and job owner (job writes Parquet to the output_uri it receives)", '{"streaming": 123, ...}', "Layer 08 /databricks/export_job_ids, layer 14", "Databricks / Data"),
    ("7. Databricks export (slide 1)", "Service principal for the export Lambda ('Can manage run'): client ID + OAuth secret entered in Secrets Manager by WBD", "mmm/<env>/databricks/export-sp", "Layer 08, 14", "Databricks"),
    ("7. Databricks export (slide 1)", "Unity Catalog storage credential + external location on landing raw/databricks/ using role mmm-<env>-databricks-uc (we give the role ARN and external ID)", "Registered by the Databricks admins", "Layer 14", "Databricks"),
    ("7. Databricks export (slide 1)", "Databricks reachability: workspace IP access list allows our NAT IPs, or PrivateLink (service name)", "NAT IPs from layer 05", "Layer 05, 14", "Databricks / Network"),
    ("8. Glue lakehouse (slide 1)", "Glue version and worker size per environment", "Glue 5.0; G.1X x 2 / 5 / 10; 120-minute timeout", "Layer 15", "Data / Architecture"),
    ("8. Glue lakehouse (slide 1)", "Is the Glue Data Catalog encryption (account-wide setting) already managed by WBD", "No - created with this list", "Layer 15", "Cloud Platform / Security"),
    ("8. Glue lakehouse (slide 1)", "AWS Lake Formation required, or IAM only", "IAM only", "Layer 15", "Security / Data"),
    ("8. Glue lakehouse (slide 1)", "Silver data-quality rules, owner, behaviour on failure", "DQDL rules from the data engineers; stop the refresh", "Layer 15 ruleset", "Data engineering"),
    ("8. Glue lakehouse (slide 1)", "Gold tables to export to RDS for the app", "<bu>_titles, <bu>_inventory_history", "Layer 15 export-rds", "Data / Backend"),
    ("9. Models (slide 1)", "Business unit names, refresh schedule and timezone", BUS + "; weekly Monday 06:00, America/New_York", "Layer 17", "Data"),
    ("9. Models (slide 1)", "Model acceptance thresholds per business unit and the named model approver", "MAPE, R2, ...; WBD approver for prod", "Layer 16, GitHub environment", "Data science"),
    ("9. Models (slide 1)", "Model results in RDS for every registered version or only approved ones", "Every registered version (tagged with the package ARN)", "Layer 13 publisher", "Data science / Backend"),
    ("9. Models (slide 1)", "Drift threshold, check schedule, retrain automatically or alert only", "0.2; daily 07:00; alert only", "Layer 17, 19", "Data science"),
    ("9. Models (slide 1)", "Third-party vendors still needed (API keys entered by WBD)", "adstra, inscape / none", "Layer 08 (optional)", "Data owners"),
    ("10. GenAI explanation (slide 2)", "Written approval for data to external LLM providers; approved providers (or Bedrock-hosted models)", "Approval document", "Layer 18", "Responsible AI / Legal"),
    ("10. GenAI explanation (slide 2)", "GenAI in Release 1 (explanation tool on every run) or Release 2", "Release 2; app works without it", "Layer 18", "Business / EY"),
    ("10. GenAI explanation (slide 2)", "Provider API keys entered in Secrets Manager by WBD", "mmm/<env>/llm/openai, anthropic, google", "Layer 08", "Vendor contracts"),
    ("10. GenAI explanation (slide 2)", "Token quota per business unit and per run; guardrail policy (PII, denied topics, thresholds)", "1,000,000 tokens/day per BU; ~5,000 per run; 0.75", "Layer 08, 18", "Responsible AI"),
    ("11. Operations, security and cost", "Alert email lists / paging tool", "mmm-oncall@<domain>", "Layer 19 SNS", "Ops"),
    ("11. Operations, security and cost", "Monthly budget per account", "3,000 / 6,000 / 15,000 USD", "Layer 04", "Finance"),
    ("11. Operations, security and cost", "Log retention; approved scenarios (Object Lock) and training-data retention", "Logs 30 / 90 / 365 d; approved 7 years; training data 1-2 years", "Layers 09, 19", "Legal / Audit"),
    ("11. Operations, security and cost", "Splunk shipping required: HEC endpoint, token (entered by WBD), index, source type", "Not required at go-live", "Layer 19 (optional)", "Splunk"),
    ("11. Operations, security and cost", "RPO / RTO sign-off; cross-region backup copy and prod vault lock", "RPO 24 h (PITR 5 min for RDS), RTO 4 h; no cross-region copy", "Layer 20", "Ops / Security"),
    ("11. Operations, security and cost", "Security incident contact, operations owner after handover, hypercare length", "Names", "Runbooks", "Security / Ops"),
    ("12. GitHub and releases", "GitHub organization / repository (OIDC trust subject)", "wbd-org/wbd-mmm-devops", "Layer 04", "GitHub admins"),
    ("12. GitHub and releases", "Repo admin rights for DevOps (environments, variables, branch protection)", "Admin role", "GitHub", "GitHub admins"),
    ("12. GitHub and releases", "Approvers: staging (EY), prod (WBD), model promotion, Glue script releases", "GitHub users / teams", "GitHub environments", "WBD / EY"),
    ("12. GitHub and releases", "CAB change-ticket format for prod", "CHG1234567", "deploy pipeline", "CAB"),
    ("12. GitHub and releases", "Approved security tools (SAST, DAST, GitHub Advanced Security)", "Semgrep / CodeQL / ZAP", "CI", "Security"),
]

# (question, proposed default)
DECISIONS = [
    ("Separate Databricks export Lambda (slide 1 shows a Lambda next to Databricks)?", "Yes - mmm-<env>-databricks-export starts and polls the export job; the results publisher only writes to RDS"),
    ("How does data leave Databricks?", "The WBD export job writes Parquet to landing raw/databricks/<bu>/<date>/ through a write-only Unity Catalog role"),
    ("Glue orchestration: Glue workflows / triggers or Step Functions?", "Step Functions (glue:startJobRun.sync per layer) inside model-refresh"),
    ("Lake Formation on the Glue catalog?", "Not used - IAM roles, bucket policies and per-BU KMS keys"),
    ("Silver data-quality failure?", "Stops the refresh and alerts (rule glue-data-quality-failed)"),
    ("Glue export to RDS: DB user and path?", "mmm_etl through RDS Proxy with an IAM token; tables from the backend migrations"),
    ("Order of the last refresh steps?", "Register the model version, then write the results to RDS (rows carry the model package ARN)"),
    ("Optimizer on ECS: one task per run or a worker service?", "One Fargate task per run started by Step Functions (isolation, simple cancel)"),
    ("Concurrency and fairness between business units?", "5 / 20 / 50 runs at a time, bounded by the Fargate quota; first come first served; per-user limits in the app"),
    ("Forecast runs ('upload future titles')?", "Same queue, state machine and optimizer image; run_type forecast"),
    ("Malware scanning of uploads?", "Not at go-live; uploads only through presigned URLs scoped to the user's BU, CORS limited to the app"),
    ("Explanation tool on every run (GenAI)?", "Behind a switch (genai_enabled); the run succeeds without the explanation"),
    ("Data leaving AWS to LLM providers?", "Off until approved; Bedrock-hosted models as the alternative"),
    ("Databricks reachability?", "NAT IPs on the workspace IP access list; PrivateLink if WBD requires"),
    ("App reachable from the internet or only WBD ranges? Shield Advanced?", "Internet + WAF + Okta sign-in; no Shield Advanced"),
    ("Sign-in at the ALB with Okta (no Cognito)?", "One Okta OIDC app per environment; groups mmm-bu-* / mmm-role-*"),
    ("Database sizes and read replica?", "Single-AZ dev, Multi-AZ staging / prod, no read replica"),
    ("Model drift above the threshold?", "Alert only; daily check switched on after the first approved model"),
    ("Lakehouse in AWS Backup?", "Yes (daily, same retention as RDS); uploads and glue-assets not backed up"),
    ("Shared tooling account / self-hosted runners?", "Not used - GitHub-hosted runners with OIDC"),
    ("Which tool WBD uses to create the resources, and who keeps the state?", "WBD decides; our Terraform can be handed over if WBD prefers it (state bucket per account, layer 02)"),
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
    q_sheet(ws, "WBD MMM v4 - inputs WBD provides before / while the infra team creates the AWS resources (fill the yellow columns per environment)",
            ["#", "Section", "What WBD provides", "Example / proposed default", "Used for (aws_resource_list_4_new.xlsx)", "WBD owner",
             "Dev value", "Staging value", "Prod value", "Status", "Notes"],
            [(i, *r, "", "", "", "Open", "") for i, r in enumerate(INPUTS, 1)],
            (5, 26, 60, 44, 30, 22, 22, 22, 22, 10, 30), input_cols=(7, 8, 9, 10, 11))
    q_sheet(wb.create_sheet("decisions_to_confirm"), "WBD MMM v4 - design decisions to confirm (proposed default until WBD answers)",
            ["#", "Question", "Proposed default", "WBD answer", "Status"],
            [(f"Q{i}", *d, "", "Open") for i, d in enumerate(DECISIONS, 1)],
            (6, 60, 70, 40, 10), input_cols=(4, 5))
    wb.save(OUT / "devops_client_question_4_new.xlsx")


build_resources()
build_questions()
print("resource rows:", len(R), "alarms/rules:", len(ALARMS), "outside:", len(OUTSIDE),
      "| inputs:", len(INPUTS), "decisions:", len(DECISIONS))

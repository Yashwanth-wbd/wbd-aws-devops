"""Builds aws_resource_list_3.xlsx and wbd_mmm_ecs_final_3.docx (v3 architecture, wbd_Presentation_3.pptx)."""
import sys
from pathlib import Path

import docx
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Pt, RGBColor
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

OUT = Path(sys.argv[1])

R1, R2 = "Release 1", "Release 2"
ALL = ("dev", "staging", "prod")
STG_PRD = ("staging", "prod")
PRD = ("prod",)

# (release, layer, resource, description, change vs v2, environments)
ROWS = [
    # 1. Account foundation
    (R1, "1. Account foundation", "AWS account", "Separate WBD-owned AWS account for the environment.", "Same", ALL),
    (R1, "1. Account foundation", "Service Control Policy (region lock)", "Blocks AWS regions that WBD has not approved.", "Same", ALL),
    (R1, "1. Account foundation", "IAM Identity Center permission sets", "SSO roles for engineers (ReadOnly/Developer/DevOps/Security/BreakGlass); no IAM users.", "Same", ALL),
    (R1, "1. Account foundation", "AWS CloudTrail", "Records every API call for audit (Operations band on the slides).", "Same", ALL),
    (R1, "1. Account foundation", "Amazon GuardDuty", "Detects threats and suspicious activity.", "Same", ALL),
    (R1, "1. Account foundation", "AWS Security Hub", "Shows all security findings in one place.", "Same", ALL),
    (R1, "1. Account foundation", "AWS Config", "Tracks resource settings and flags non-compliant ones.", "Same", ALL),
    (R1, "1. Account foundation", "Amazon Inspector", "Scans ECR images (api, ui, SageMaker optimizer/training images).", "Same", ALL),
    (R1, "1. Account foundation", "IAM Access Analyzer", "Finds resources shared outside the account by mistake.", "Same", ALL),
    (R1, "1. Account foundation", "S3 Block Public Access (account level)", "Stops any S3 bucket from being made public.", "Same", ALL),
    (R1, "1. Account foundation", "EBS encryption by default", "Makes every new disk encrypted automatically.", "Same", ALL),
    (R1, "1. Account foundation", "KMS keys", "Keys per purpose: state, ECR, RDS, S3 (+ per BU), logs, secrets, SageMaker, SQS (new in v3), GenAI.", "Changed", ALL),
    (R1, "1. Account foundation", "KMS key policies", "Control which roles and AWS services can use each key (incl. SQS for the API and dispatcher).", "Changed", ALL),
    (R1, "1. Account foundation", "S3 bucket - Terraform state", "Stores Terraform state (versioned, encrypted, S3 lock file).", "Same", ALL),
    (R1, "1. Account foundation", "IAM permission boundary", "Attached to every Terraform-created role, incl. the dispatcher Lambda and model-monitor state machine roles.", "Same", ALL),
    (R1, "1. Account foundation", "IAM OIDC identity provider (GitHub)", "Lets GitHub Actions log in to AWS without stored keys.", "Same", ALL),
    (R1, "1. Account foundation", "IAM roles - GitHub Actions", "gha-plan, gha-apply, gha-deploy (ECS, SSM image pointers, publisher alias, RDS snapshot), gha-ecr-push/read, model-eval, model-approve.", "Changed", ALL),
    (R1, "1. Account foundation", "AWS Budgets", "Alerts when spend reaches 50/80/100% of budget.", "Same", ALL),
    (R1, "1. Account foundation", "Cost Anomaly Detection monitor", "Alerts on unexpected spend increases.", "Same", ALL),
    (R1, "1. Account foundation", "Amazon Macie (optional)", "Finds sensitive data stored in S3 buckets.", "Same", ALL),
    # 2. Networking
    (R1, "2. Networking", "VPC", "Private network for the environment (/19).", "Same", ALL),
    (R1, "2. Networking", "Public subnets", "Hold the public ALB (public entry) and NAT gateways.", "Same", ALL),
    (R1, "2. Networking", "Private-app subnets", "ECS tasks (ui, api), results-publisher and dispatcher Lambdas, SageMaker job ENIs.", "Changed", ALL),
    (R1, "2. Networking", "Private-data subnets", "Hold RDS PostgreSQL with no internet access.", "Changed", ALL),
    (R1, "2. Networking", "Private-endpoint subnets", "Hold VPC interface endpoints.", "Same", ALL),
    (R1, "2. Networking", "Internet Gateway", "Connects public subnets to the internet (ALB also reaches the Okta token endpoint).", "Same", ALL),
    (R1, "2. Networking", "Elastic IP (for NAT)", "Fixed public IP used by each NAT gateway.", "Same", ALL),
    (R1, "2. Networking", "NAT Gateway", "Outbound only; also the egress to Databricks and (Release 2) LLM providers.", "Same", ALL),
    (R1, "2. Networking", "Route tables + associations", "Public -> IGW, app -> NAT, data/endpoint -> no internet.", "Same", ALL),
    (R1, "2. Networking", "VPC gateway endpoints (S3, DynamoDB)", "Private, free access to S3 and DynamoDB.", "Same", ALL),
    (R1, "2. Networking", "VPC interface endpoints", "ECR api/dkr, STS, Secrets Manager, SSM, SSM Messages, KMS, Logs, Monitoring, X-Ray, Step Functions, SageMaker API + NEW SQS.", "Changed", ALL),
    (R1, "2. Networking", "Security group - VPC endpoints", "Allows HTTPS (443) from inside the VPC.", "Same", ALL),
    (R1, "2. Networking", "Security group - ALB", "HTTPS from the internet or WBD ranges; egress to targets and to Okta (OIDC token endpoint).", "Changed", ALL),
    (R1, "2. Networking", "Security group - ECS ui service", "Allows traffic to UI tasks only from the ALB.", "Same", ALL),
    (R1, "2. Networking", "Security group - ECS api service", "Allows traffic to API tasks only from the ALB.", "Same", ALL),
    (R1, "2. Networking", "Security group - SageMaker jobs", "No inbound; outbound 443 to VPC endpoints and the S3 prefix list.", "Same", ALL),
    (R1, "2. Networking", "Security group - Lambda functions", "No inbound; publisher -> RDS Proxy + endpoints; dispatcher -> endpoints (SQS, Step Functions, SSM).", "Changed", ALL),
    (R1, "2. Networking", "Security group - RDS Proxy", "DB connections only from API tasks, the migrate task and the results publisher.", "Same", ALL),
    (R1, "2. Networking", "Security group - RDS PostgreSQL", "DB traffic only from RDS Proxy (replaces the Aurora SG).", "Changed", ALL),
    (R1, "2. Networking", "S3 bucket - logs", "ALB access logs and S3 access logs.", "Same", ALL),
    (R1, "2. Networking", "VPC Flow Logs", "Records network traffic for security checks.", "Same", ALL),
    (R1, "2. Networking", "Transit Gateway attachment (optional)", "Connects the VPC to WBD's network (VDI, Splunk, Databricks).", "Same", ALL),
    (R1, "2. Networking", "Databricks PrivateLink endpoints (optional)", "Workspace (front-end/REST) endpoint.", "Same", ALL),
    (R1, "2. Networking", "Route 53 private hosted zone (Databricks PrivateLink)", "Private DNS for the Databricks endpoint.", "Same", ALL),
    (R1, "2. Networking", "Route 53 Resolver outbound endpoint + rules (optional)", "Resolves WBD internal names over the Transit Gateway.", "Same", ALL),
    # 3. Container registry
    (R1, "3. Container registry", "ECR repositories", "One registry per environment: mmm/api, mmm/ui, mmm/sagemaker-optimizer, mmm/sagemaker-training.", "Same", ALL),
    (R1, "3. Container registry", "ECR lifecycle policy", "Deletes old untagged images to save cost.", "Same", ALL),
    (R1, "3. Container registry", "ECR tag immutability + enhanced scanning", "Stops tags being overwritten and scans every image.", "Same", ALL),
    (R1, "3. Container registry", "Image promotion (pipeline step)", "Same digest copied dev -> staging -> prod on rc/release tags, incl. SageMaker images.", "Same", ALL),
    # 4. Security & secrets
    (R1, "4. Security & secrets", "Secrets Manager secrets", "DB users, Splunk, third parties, LLM keys (R2) + NEW mmm/<env>/okta/alb-client (Okta OIDC client secret for the ALB).", "Changed", ALL),
    (R1, "4. Security & secrets", "SSM Parameter Store parameters", "genai_enabled, databricks/host, SageMaker image pointers, token quotas + NEW optimization/max_concurrent_runs, okta/issuer; cognito/* removed.", "Changed", ALL),
    # 5. Identity
    (R1, "5. Identity & login", "WBD Okta OIDC app (per environment)", "Enterprise identity provider on slide 2; sign-in redirect https://<app>/oauth2/idpresponse; groups claim; MFA (WBD Identity team).", "New", ALL),
    (R1, "5. Identity & login", "ALB authenticate-oidc action (Okta)", "ALB signs users in with Okta before /* reaches the UI; /api/* returns 401 when not signed in.", "New", ALL),
    (R1, "5. Identity & login", "Okta groups claim -> app RBAC", "API maps mmm-bu-* / mmm-role-* groups from the ALB-signed header to BU + role; PostgreSQL RLS per BU.", "Changed", ALL),
    # 6. Data & storage
    (R1, "6. Data & storage", "S3 bucket - landing", "Raw source data by feed and date; 3+ years history; BU key enforced under <bu>/.", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - lakehouse (Delta Lake)", "Bronze / Silver / Gold Delta tables + NEW monitoring/<bu>/<date>/ features for drift checks (90-day expiry).", "Changed", ALL),
    (R1, "6. Data & storage", "S3 bucket - training data", "Immutable Parquet + metadata exported from Gold (Object Lock).", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - models", "Artifacts, evaluation (+ NEW predictions/, lift/, manifest), approved curves + NEW baseline/<bu>/ and monitoring/<bu>/ drift reports.", "Changed", ALL),
    (R1, "6. Data & storage", "S3 bucket - results (run outputs)", "Full run evidence of every optimization (runs/<run_id>/input, output).", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - approved (Object Lock)", "Approved scenarios that cannot be changed.", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - exports", "Excel exports, auto-deleted after 30 days.", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket policies", "HTTPS-only and deny unencrypted uploads on every bucket.", "Same", ALL),
    (R1, "6. Data & storage", "S3 EventBridge notifications (landing bucket)", "Sends 'new file' events to EventBridge (optional refresh trigger).", "Same", ALL),
    (R1, "6. Data & storage", "IAM role - Databricks Unity Catalog", "Landing, lakehouse, training-data + NEW read models/evaluation/ (write-back) and write lakehouse/monitoring/.", "Changed", ALL),
    (R1, "6. Data & storage", "KMS keys per business unit (S3)", "BU data isolation for landing, lakehouse and training data.", "Same", ALL),
    (R1, "6. Data & storage", "DB subnet group", "Private-data subnets for RDS PostgreSQL.", "Changed", ALL),
    (R1, "6. Data & storage", "RDS DB parameter group", "rds.force_ssl, pgaudit, slow-query logging.", "Changed", ALL),
    (R1, "6. Data & storage", "RDS for PostgreSQL DB instance", "Plans, runs, allocations, audit. 16.x, gp3 + storage autoscaling, IAM auth, KMS, Performance Insights; Multi-AZ in stg/prd; deletion protection in prod. Replaces Aurora.", "New", ALL),
    (R1, "6. Data & storage", "RDS read replica (optional)", "Only if reporting / QA dashboard load needs it [ASK].", "New", PRD),
    (R1, "6. Data & storage", "IAM role - RDS Enhanced Monitoring", "OS metrics; Performance Insights on.", "Same", ALL),
    (R1, "6. Data & storage", "RDS master password in Secrets Manager (auto-rotation)", "RDS creates and rotates the admin password.", "Same", ALL),
    (R1, "6. Data & storage", "IAM role - RDS Proxy", "Lets RDS Proxy read the DB user secrets.", "Same", ALL),
    (R1, "6. Data & storage", "RDS Proxy", "Pools connections from ECS and the publisher Lambda to RDS (IAM auth, TLS).", "Changed", ALL),
    # 7. ECS compute
    (R1, "7. ECS compute", "ECS cluster (Fargate)", "Serverless container cluster with Container Insights enhanced.", "Same", ALL),
    (R1, "7. ECS compute", "Service Quotas increase (Fargate vCPU)", "Raise Fargate vCPU limit before load tests and go-live.", "Same", STG_PRD),
    (R1, "7. ECS compute", "IAM role - ECS task execution", "Pulls images, writes logs and reads listed secrets.", "Same", ALL),
    (R1, "7. ECS compute", "IAM roles - ECS task roles", "api (NEW sqs:SendMessage on the run queue instead of states:StartExecution), ui, migrate, platform-check.", "Changed", ALL),
    (R1, "7. ECS compute", "CloudWatch log groups (per service)", "Logs per ECS service with retention and KMS.", "Same", ALL),
    (R1, "7. ECS compute", "CloudWatch Logs data protection policy (optional)", "Masks personal data if it appears in logs.", "Same", ALL),
    (R1, "7. ECS compute", "ECS task definition - migrate", "One-off task that runs DB migrations before each deploy.", "Same", ALL),
    (R1, "7. ECS compute", "ECS task definition - api", "FastAPI + LangGraph tools + QA dashboard; env OPTIMIZATION_QUEUE_URL, OKTA_ISSUER (no Cognito IDs).", "Changed", ALL),
    (R1, "7. ECS compute", "ECS task definition - ui", "React + TypeScript web container (nginx, non-root); LOGOUT_URL = Okta sign-out.", "Changed", ALL),
    (R1, "7. ECS compute", "ACM certificate (project region)", "App name on the public ALB (issued by WBD).", "Same", ALL),
    (R1, "7. ECS compute", "Application Load Balancer (public entry)", "User-facing HTTPS entry; routes /api/* to API and /* to UI.", "Same", ALL),
    (R1, "7. ECS compute", "ALB target groups (ip) - ui and api", "Health checks /healthz (UI) and /api/health (API).", "Same", ALL),
    (R1, "7. ECS compute", "ALB HTTPS listener + rules", "Path routing + authenticate-oidc (Okta) instead of authenticate-cognito; HTTP -> HTTPS redirect.", "Changed", ALL),
    (R1, "7. ECS compute", "ECS service - mmm-api", "API tasks behind the ALB (circuit breaker on).", "Same", ALL),
    (R1, "7. ECS compute", "ECS service - mmm-ui", "UI web tasks behind the ALB (circuit breaker on).", "Same", ALL),
    (R1, "7. ECS compute", "Application Auto Scaling policies", "CPU target 60 % for api and ui.", "Same", ALL),
    # 8. Edge
    (R1, "8. Edge & front door", "AWS WAF web ACL (regional, on the ALB)", "Managed rules + rate limit in front of the ALB.", "Same", ALL),
    (R1, "8. Edge & front door", "WAF logging configuration", "WAF logs to aws-waf-logs-* log group (-> Splunk).", "Same", ALL),
    (R1, "8. Edge & front door", "Route 53 DNS records", "mmm-dev / mmm-stg / mmm -> ALB (WBD DNS or our zone).", "Same", ALL),
    # 9. Optimization engine
    (R1, "9. Optimization engine", "SQS queue - optimization requests", "API sends one message per run (run_id, BU, input URI); Standard queue, SSE-KMS, long polling, TLS-only policy.", "New", ALL),
    (R1, "9. Optimization engine", "SQS dead-letter queue", "Messages that fail repeatedly (maxReceiveCount 10); alarm when not empty; redrive runbook.", "New", ALL),
    (R1, "9. Optimization engine", "Lambda function - message dispatcher", "Starts optimization executions from the queue while RUNNING < max_concurrent_runs; returns the rest to the queue.", "New", ALL),
    (R1, "9. Optimization engine", "IAM role + log group - dispatcher", "Consume the queue, StartExecution/ListExecutions on the optimization state machine, read SSM, put metrics.", "New", ALL),
    (R1, "9. Optimization engine", "Lambda event source mapping (SQS -> dispatcher)", "Batch 10, maximum concurrency 2, partial batch failures.", "New", ALL),
    (R1, "9. Optimization engine", "IAM role - SageMaker optimization jobs", "Reads models + response curves, writes run outputs, VPC + KMS.", "Same", ALL),
    (R1, "9. Optimization engine", "SSM parameters - SageMaker image pointers", "/mmm/<env>/images/sagemaker-* = image digest, written by deploy.yml.", "Same", ALL),
    (R1, "9. Optimization engine", "Step Functions state machine - optimization", "Async run: image pointer -> SageMaker Processing job -> publisher; now started by the dispatcher.", "Changed", ALL),
    (R1, "9. Optimization engine", "IAM role + log group - optimization state machine", "Run SageMaker jobs and invoke the publisher; logs.", "Same", ALL),
    (R1, "9. Optimization engine", "SageMaker job - optimization & decision (runtime)", "Processing job from mmm/sagemaker-optimizer (Model Summarizer, Optimizer, Simulation); runs in the VPC.", "Same", ALL),
    (R1, "9. Optimization engine", "Lambda function - results publisher", "Writes plans, runs and allocations from S3 outputs to RDS PostgreSQL (alias live).", "Changed", ALL),
    (R1, "9. Optimization engine", "IAM role + log group - results publisher", "Least-privilege role (rds-db:connect via Proxy, read run output), logs.", "Same", ALL),
    (R1, "9. Optimization engine", "SageMaker service quotas", "Processing instance quota >= max_concurrent_runs in each environment.", "Changed", ALL),
    # 10. Data & ML platform
    (R1, "10. Data & ML platform", "EventBridge Scheduler - scheduled refresh", "Starts the model-refresh state machine per BU on schedule.", "Same", ALL),
    (R1, "10. Data & ML platform", "EventBridge rule - manual / app-triggered refresh", "mmm.refresh events from the API, operators or the drift check.", "Changed", ALL),
    (R1, "10. Data & ML platform", "EventBridge connection (Databricks OAuth)", "Credentials for the Step Functions HTTP Tasks that run Lakeflow jobs.", "Same", ALL),
    (R1, "10. Data & ML platform", "Step Functions state machine - model refresh", "Lakeflow job -> train -> evaluate -> register -> NEW write-back job (predictions, lift, evaluation -> Gold).", "Changed", ALL),
    (R1, "10. Data & ML platform", "IAM role + log group - model refresh state machine", "HTTP Task, SageMaker jobs, registry; logs.", "Same", ALL),
    (R1, "10. Data & ML platform", "Databricks Lakeflow Jobs - refresh / feature export", "Ingestion -> Bronze -> Silver -> Gold -> Feature Export (+ purpose=monitor export for drift).", "Changed", ALL),
    (R1, "10. Data & ML platform", "Databricks Lakeflow Job - write-back", "MERGE model predictions, lift and evaluation results into per-BU Gold tables (data engineers).", "New", ALL),
    (R1, "10. Data & ML platform", "Unity Catalog storage credential + external locations", "Delta Lake tables on the lakehouse bucket + read-only models/evaluation/; lineage on.", "Changed", ALL),
    (R1, "10. Data & ML platform", "IAM roles - SageMaker training + evaluation", "Read training data, write models, register packages; NEW drift job: read lakehouse/monitoring, put ModelDrift metric.", "Changed", ALL),
    (R1, "10. Data & ML platform", "SageMaker training job (runtime)", "Trains/tunes multi-stage models from the Parquet files; writes the drift baseline with the artifact.", "Changed", ALL),
    (R1, "10. Data & ML platform", "SageMaker processing job - evaluation (runtime)", "Baseline -> channel lift -> title adjustment; writes evaluation.json, curves/, predictions/, lift/.", "Changed", ALL),
    (R1, "10. Data & ML platform", "SageMaker Model Registry - model versions", "PendingManualApproval -> Approved by model-governance.yml (publishes curves + baseline).", "Changed", ALL),
    (R1, "10. Data & ML platform", "EventBridge rule - model package state change", "Model package state changes -> SNS.", "Same", ALL),
    (R1, "10. Data & ML platform", "Step Functions state machine - model monitor (drift)", "Per BU: Databricks monitor export -> SageMaker drift job -> optional mmm.refresh when drift > threshold.", "New", ALL),
    (R1, "10. Data & ML platform", "IAM role + log group - model monitor state machine", "HTTP Task, drift Processing jobs, PassRole, PutEvents (mmm.refresh); logs.", "New", ALL),
    (R1, "10. Data & ML platform", "EventBridge Scheduler - drift check", "One schedule per BU (daily, cron(0 7 * * ? *); off until the first approved baseline).", "New", ALL),
    (R1, "10. Data & ML platform", "SageMaker processing job - drift (runtime)", "Training image with argument drift; compares new features / predictions with the approved baseline; writes drift.json.", "New", ALL),
    (R1, "10. Data & ML platform", "SageMaker Model Monitor (managed)", "Endpoint / batch-transform feature; no endpoint in this design.", "New", ALL),
    # 11. Monitoring
    (R1, "11. Monitoring & logging", "SNS topic (alerts)", "Alarm notifications to email/Teams.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch Container Insights", "Health and usage of ECS services and tasks.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch Application Signals (optional)", "API latency, errors and traces.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch alarms", "API/ALB, availability, Step Functions, Lambda, RDS (replaces Aurora), SQS oldest message + DLQ, dispatcher errors, model drift, model monitor failed, cert expiry, refresh overdue.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "EventBridge rules -> SNS", "GuardDuty High, ECS deployment failure, break-glass, backup failed, model package state.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch dashboards", "Platform, api-ui, optimization (+ queue), training (+ write-back, drift), rds (replaces aurora), cost, genai.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "Kinesis Data Firehose (to Splunk) + roles + subscription filters", "Delivers logs into WBD Splunk incl. dispatcher and model-monitor logs.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch Synthetics canary (optional)", "Logs in and checks the app every few minutes.", "Same", STG_PRD),
    # 12. Backup
    (R1, "12. Backup & DR", "RDS automated backups / PITR", "Restore the DB instance to any point in time (7/14/35 days).", "Changed", ALL),
    (R1, "12. Backup & DR", "AWS Backup vault", "Encrypted store for backups (vault lock in prod).", "Same", ALL),
    (R1, "12. Backup & DR", "AWS Backup plan + selection", "Daily: RDS instance (replaces Aurora), results, approved, models, training data, lakehouse.", "Changed", ALL),
    (R1, "12. Backup & DR", "Cross-region backup copy (optional)", "Copies backups to a second region if WBD approves.", "Same", PRD),
    # 13. Release 2
    (R2, "13. Release 2 - GenAI", "SSM parameters - genai_enabled flag + token quotas", "GenAI on/off without redeploy; per-BU token limits.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "Secrets Manager - LLM provider keys", "mmm/<env>/llm/openai, anthropic, google.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "Amazon API Gateway - LLM gateway (private REST API)", "Single entry from the API (LangGraph tools) to OpenAI / Anthropic / Google models.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "Lambda - LLM proxy", "Adds the provider key and applies the guardrail to prompt and answer.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "VPC interface endpoints - execute-api, Bedrock runtime", "Private gateway and ApplyGuardrail calls.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "Bedrock Guardrails", "Prompt attack, PII masking/blocking, grounding checks for every provider.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "CloudWatch alarms + dashboard - GenAI", "Gateway 4xx/5xx/latency, guardrail interventions, token quota per BU.", "Same", ALL),
]

REMOVED = [
    ("Amazon Cognito user pool", "Slide 2 shows 'SSO / Authentication - Okta'; the ALB signs in with Okta directly (OIDC)", "5. Identity & login"),
    ("Cognito identity provider (Okta SAML)", "Okta OIDC app per environment, used by the ALB", "5. Identity & login"),
    ("Cognito app client + hosted domain", "ALB authenticate-oidc with the Okta client (secret in Secrets Manager)", "5. Identity & login"),
    ("ALB authenticate-cognito action", "ALB authenticate-oidc action", "7. ECS compute"),
    ("SSM parameters cognito/user_pool_id, cognito/client_id + API env COGNITO_*", "SSM okta/issuer + API env OKTA_ISSUER", "4. Security & secrets"),
    ("Aurora PostgreSQL Serverless v2 cluster + instances", "RDS for PostgreSQL DB instance (slide 2)", "6. Data & storage"),
    ("Aurora cluster parameter group", "RDS DB parameter group", "6. Data & storage"),
    ("Aurora alarms (ACU, free local storage, replica lag) + aurora dashboard", "RDS alarms + rds dashboard", "11. Monitoring & logging"),
    ("Aurora cluster snapshot in deploy.yml + GitHub variable AURORA_CLUSTER_ID", "RDS DB snapshot + DB_INSTANCE_ID", "CI/CD"),
    ("states:StartExecution on the API task role", "API sends to SQS; only the dispatcher starts executions", "7. ECS compute"),
]

# Repo today (v2 build) -> v3 action; rows not listed get a default from the change column.
WBD = "WBD account baseline - verified, not built by this repo"
STATUS = {
    "AWS account": WBD, "Service Control Policy (region lock)": WBD, "IAM Identity Center permission sets": WBD,
    "AWS CloudTrail": WBD, "Amazon GuardDuty": WBD, "AWS Security Hub": WBD, "AWS Config": WBD,
    "Amazon Inspector": WBD + " (ECR enhanced scanning is built)", "IAM Access Analyzer": WBD,
    "S3 Block Public Access (account level)": WBD, "EBS encryption by default": WBD, "Amazon Macie (optional)": WBD,
    "KMS keys": "Built - add purpose sqs (modules/kms)",
    "KMS key policies": "Built - add SQS usage for the API role and dispatcher",
    "IAM roles - GitHub Actions": "Built - deploy role: RDS create-db-snapshot instead of the Aurora cluster snapshot",
    "Private-app subnets": "Built - no change to subnets; dispatcher Lambda added",
    "Private-data subnets": "Built - RDS instead of Aurora",
    "VPC interface endpoints": "Built - add sqs endpoint (modules/network)",
    "Security group - ALB": "Built - check egress 443 to Okta",
    "Security group - Lambda functions": "Built (lambda SG) - reused by the dispatcher",
    "Security group - RDS PostgreSQL": "Built as the Aurora SG - rename/repurpose",
    "Transit Gateway attachment (optional)": "Built, off (enable_transit_gateway)",
    "Databricks PrivateLink endpoints (optional)": "Built, off (enable_databricks_privatelink)",
    "Route 53 private hosted zone (Databricks PrivateLink)": "Built, off (with PrivateLink)",
    "Route 53 Resolver outbound endpoint + rules (optional)": "Built, off (enable_resolver_forwarding)",
    "Secrets Manager secrets": "Built - add okta/alb-client",
    "SSM Parameter Store parameters": "Built - add optimization/max_concurrent_runs, okta/issuer; remove cognito/*",
    "WBD Okta OIDC app (per environment)": "WBD Identity team creates it from terraform output okta_app_settings (not Terraform)",
    "ALB authenticate-oidc action (Okta)": "Not built - replace authenticate-cognito (modules/alb, frontdoor.tf)",
    "Okta groups claim -> app RBAC": "Backend team (API); groups now come from the Okta ID token instead of custom:groups",
    "S3 bucket - lakehouse (Delta Lake)": "Built, off (enable_data_platform) - add monitoring/ prefix + expiry rule",
    "S3 bucket - models": "Built - new prefixes only (no Terraform change except IAM)",
    "S3 bucket - training data": "Built, off (enable_data_platform)",
    "IAM role - Databricks Unity Catalog": "Built, off - add read models/evaluation/*, write lakehouse/monitoring/*",
    "KMS keys per business unit (S3)": "Built, off (enable_data_platform)",
    "DB subnet group": "Built (Aurora) - move to modules/rds",
    "RDS DB parameter group": "Not built - replaces the Aurora cluster parameter group",
    "RDS for PostgreSQL DB instance": "Not built - new modules/rds replaces modules/aurora",
    "RDS read replica (optional)": "Not planned by default [ASK]",
    "RDS Proxy": "Built (Aurora target) - retarget to the RDS instance",
    "Service Quotas increase (Fargate vCPU)": "Manual request before load test",
    "IAM roles - ECS task roles": "Built - api: sqs:SendMessage instead of states:StartExecution",
    "ECS task definition - api": "Built - env changes (ecs.tf, ecs/<env>/api.json)",
    "ECS task definition - ui": "Built - LOGOUT_URL from Okta",
    "ALB HTTPS listener + rules": "Built - authenticate-oidc instead of authenticate-cognito",
    "Route 53 DNS records": "Built if route53_zone_id is set; otherwise WBD DNS adds the CNAME",
    "SQS queue - optimization requests": "Not built - new queue module",
    "SQS dead-letter queue": "Not built - new (queue module)",
    "Lambda function - message dispatcher": "Not built - new (DevOps code, shipped by Terraform)",
    "IAM role + log group - dispatcher": "Not built - new",
    "Lambda event source mapping (SQS -> dispatcher)": "Not built - new",
    "Step Functions state machine - optimization": "Built - definition unchanged; StartExecution moves from the API to the dispatcher",
    "Lambda function - results publisher": "Built - DB host = RDS Proxy of the new instance",
    "SageMaker service quotas": "Manual quota request (>= max_concurrent_runs)",
    "EventBridge Scheduler - scheduled refresh": "Built, off (enable_data_platform + enable_model_refresh_schedule)",
    "EventBridge rule - manual / app-triggered refresh": "Built, off - also targeted by the drift check",
    "EventBridge connection (Databricks OAuth)": "Built, off (enable_data_platform)",
    "Step Functions state machine - model refresh": "Built, off - add write-back states after RegisterModel",
    "IAM role + log group - model refresh state machine": "Built, off",
    "Databricks Lakeflow Jobs - refresh / feature export": "Data engineers (bundle) - add purpose=monitor mode",
    "Databricks Lakeflow Job - write-back": "Data engineers (bundle); job id -> databricks_writeback_job_id",
    "Unity Catalog storage credential + external locations": "WBD Databricks admins; IAM role is built - add read-only external location on models/evaluation/",
    "IAM roles - SageMaker training + evaluation": "Built, off - add drift permissions",
    "SageMaker training job (runtime)": "Built, off - data scientists add the baseline output",
    "SageMaker processing job - evaluation (runtime)": "Built, off - data scientists add predictions/, lift/, manifest.json",
    "SageMaker Model Registry - model versions": "Built - model-governance.yml also publishes models/baseline/<bu>/ and approval.json",
    "EventBridge rule - model package state change": "Built -> SNS",
    "Step Functions state machine - model monitor (drift)": "Not built - new (data.tf, enable_data_platform)",
    "IAM role + log group - model monitor state machine": "Not built - new",
    "EventBridge Scheduler - drift check": "Not built - new, off by default (enable_model_monitor_schedule)",
    "SageMaker processing job - drift (runtime)": "Not built - new; drift code by the data scientists",
    "SageMaker Model Monitor (managed)": "Not planned - no endpoint; drift runs as a Processing job",
    "CloudWatch Application Signals (optional)": "Built, off (enable_application_signals)",
    "CloudWatch alarms": "Built - replace Aurora alarms with RDS; add SQS, DLQ, dispatcher, drift, model-monitor alarms",
    "CloudWatch dashboards": "Built - aurora -> rds; extend optimization and training",
    "Kinesis Data Firehose (to Splunk) + roles + subscription filters": "Built, off (enable_splunk_shipping) - add the new log groups",
    "CloudWatch Synthetics canary (optional)": "Not built (gap) - deploy smoke test + optimization dry run instead",
    "RDS automated backups / PITR": "Built for Aurora - same settings on the RDS instance",
    "AWS Backup vault": "Built (vault lock in prod)",
    "AWS Backup plan + selection": "Built - RDS instance instead of the Aurora cluster",
    "Cross-region backup copy (optional)": "Built, off (enable_cross_region_copy)",
}
for _r in ROWS:
    if _r[0] == R2:
        STATUS.setdefault(_r[2], "Built, off (enable_genai) - no change")


def status_of(res, change):
    if res in STATUS:
        return STATUS[res]
    return {"Same": "Built - keep", "Changed": "Built - change", "New": "Not built - add"}[change]


# Implementation result (6 Nov 2026); rows not listed get a default from the plan status.
IMPL_DONE = "Implemented, validated offline (apply pending accounts)"
IMPL = {
    "KMS keys": "Implemented - purpose sqs added",
    "VPC interface endpoints": "Implemented - sqs endpoint added",
    "Security group - ALB": "Implemented - egress 443 for the Okta token / user info calls",
    "Security group - RDS PostgreSQL": "Implemented - rds SG, PostgreSQL from RDS Proxy only",
    "Secrets Manager secrets": "Implemented - okta/alb-client (read by Terraform once okta_sign_in_enabled = true)",
    "ALB authenticate-oidc action (Okta)": "Implemented - modules/alb + frontdoor.tf; okta_sign_in_enabled switch (503 until on)",
    "DB subnet group": "Implemented - in modules/rds",
    "RDS DB parameter group": "Implemented - modules/rds (rds.force_ssl, pgaudit)",
    "RDS for PostgreSQL DB instance": "Implemented - modules/rds; modules/aurora deleted",
    "RDS Proxy": "Implemented - modules/rds, target = the RDS instance",
    "SQS queue - optimization requests": "Implemented - modules/run-queue (run-queue.tf), KMS key sqs",
    "SQS dead-letter queue": "Implemented - modules/run-queue (maxReceiveCount 10, ~60 min)",
    "Lambda function - message dispatcher": "Implemented - modules/run-queue (generic DevOps code, shipped by Terraform; limit from SSM)",
    "IAM role + log group - dispatcher": "Implemented - modules/run-queue",
    "Lambda event source mapping (SQS -> dispatcher)": "Implemented - modules/run-queue",
    "Step Functions state machine - model refresh": "Implemented, off (enable_data_platform) - write-back states after RegisterModel",
    "Step Functions state machine - model monitor (drift)": "Implemented, off (enable_data_platform) - data.tf",
    "IAM role + log group - model monitor state machine": "Implemented, off (enable_data_platform)",
    "EventBridge Scheduler - drift check": "Implemented, off (enable_model_monitor_schedule) - daily cron(0 7 * * ? *) instead of the weekly default",
    "SageMaker Model Registry - model versions": "Implemented - model-governance.yml publishes curves + baseline and writes approval.json",
    "CloudWatch alarms": "Implemented - rds-*, runs-*, model-drift-<bu>, model-monitor-failed",
    "CloudWatch dashboards": "Implemented - rds dashboard; optimization (+ run queue) and training (+ drift) extended",
    "AWS Backup plan + selection": "Implemented - RDS instance",
    "RDS automated backups / PITR": "Implemented - PITR 7 / 14 / 35 days",
}


def impl_of(res, status):
    if res in IMPL:
        return IMPL[res]
    if status.startswith(("WBD", "Not planned", "Manual", "Data engineers", "Backend team", "Unity Catalog")):
        return "Not DevOps / not planned - see plan column"
    if status.startswith("Not built (gap)"):
        return "Gap - not built"
    return "Implemented, off by default (apply pending accounts)" if "off" in status.split(" - ")[0] else IMPL_DONE


# (question, proposed default, still to confirm with WBD)
DECISIONS = [
    ("Okta at the ALB - OIDC or SAML? One app per environment? Groups claim?", "OIDC web app per environment (ALB only supports OIDC); groups claim with mmm-bu-* / mmm-role-*; MFA in Okta; client secret in Secrets Manager mmm/<env>/okta/alb-client", "Yes - WBD Identity"),
    ("ALB sign-in or app-level OIDC (PKCE in the UI, JWT check in the API)?", "ALB authenticate-oidc - no auth code in the UI; the API trusts the ALB-signed x-amzn-oidc-data header", "Yes"),
    ("Okta client secret in the Terraform state acceptable?", "Read from Secrets Manager by a data source; only stored in the encrypted, access-restricted state bucket", "Yes - WBD Security"),
    ("RDS PostgreSQL - version, instance classes, Multi-AZ instance or cluster, read replica?", "16.x; dev db.t4g.medium single-AZ, staging db.r6g.large Multi-AZ, prod db.r6g.xlarge Multi-AZ; gp3 + storage autoscaling; no read replica; RDS Proxy kept", "Yes - sizes after load test"),
    ("SQS - Standard or FIFO?", "Standard + DLQ (maxReceiveCount 10); duplicates harmless because the execution name is the run_id", "No"),
    ("How many optimization runs at the same time?", "max_concurrent_runs in SSM: dev 5, staging 20, prod 50 (<= SageMaker Processing quota); the dispatcher holds the rest in the queue", "Yes - with the SageMaker quota"),
    ("Fairness between BUs / users in the queue?", "Not in v3 (order of arrival); per-BU limits can be added in the dispatcher later", "Yes"),
    ("How long may a run wait in the queue?", "30 minutes (max_queue_wait_minutes), then dropped with metric ExpiredRunRequests; the API shows 'timed out in queue'", "Yes"),
    ("Dispatcher - Lambda (slide) or EventBridge Pipes? Owner?", "Lambda as on the slide; DevOps-owned generic code (no business logic, no DB access), shipped by Terraform", "No"),
    ("Write-back - what, which Gold tables, every candidate or only approved?", "Predictions, lift and metrics of every registered version keyed by refresh_id + version; approval status from approval.json; Gold <bu>_model_results; job by the data engineers", "Yes - data team"),
    ("Write-back failure?", "Fails the model-refresh execution and alarms; the registered model stays", "No"),
    ("Model drift - definition, frequency, thresholds?", "Daily per BU (schedule off until the first approved baseline); score 0-1, threshold 0.2; data scientists' drift code compares new features / predictions with the approved baseline; thresholds in data/model-thresholds.yaml (drift:)", "Yes - data science + WBD"),
    ("Drift above threshold - alert or retrain automatically?", "Alert only (auto_refresh_on_drift = false); true puts an mmm.refresh event for the BU", "Yes"),
    ("SageMaker Model Monitor (managed)?", "Not used - needs an endpoint or batch transform; drift runs as a Processing job (may use the Model Monitor container image)", "No"),
    ("Drift inputs?", "Feature-export job with purpose=monitor -> lakehouse/monitoring/<bu>/<date>/ (90-day expiry); approved baseline in models/baseline/<bu>/ (published on approval)", "No"),
    ("Still open from v2", "Q1 ALB reachability / Shield Advanced; Q3 LLM data egress approval; Q4 Databricks IP access list; Q6 Databricks service principals; Anthropic via Bedrock; shared account. Q2 answered by SQS + dispatcher", "Yes"),
]

YELLOW = PatternFill("solid", fgColor="FFF2CC")
GREEN = PatternFill("solid", fgColor="E2EFDA")
GREY = PatternFill("solid", fgColor="E7E6E6")
HEAD = PatternFill("solid", fgColor="1F3864")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def header_row(ws, row):
    for c in ws[row]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD
        c.border = BORDER
        c.alignment = Alignment(vertical="center", wrap_text=True)


def body_row(ws, fill=None):
    for c in ws[ws.max_row]:
        c.border = BORDER
        c.alignment = Alignment(vertical="top", wrap_text=True)
        if fill:
            c.fill = fill


def build_xlsx():
    wb = Workbook()
    wb.remove(wb.active)
    for env in ALL:
        ws = wb.create_sheet(env)
        ws["A1"] = f"WBD MMM - {env.capitalize()} - AWS resources in creation order (v3: Okta SSO, RDS PostgreSQL, SQS dispatch, write-back, drift - from wbd_Presentation_3.pptx)"
        ws["A1"].font = Font(bold=True, size=13)
        ws["A2"] = ("Step numbers match across Dev, Staging and Prod. Yellow = new in v3, green = changed vs v2 "
                    "(aws_resource_list_2.xlsx / the v2 build), grey = owned by WBD or not built. Removed v2 resources are on the "
                    "'removed_vs_v2' sheet; defaults for the [ASK] items are on the 'decisions' sheet. Implemented and validated offline "
                    "on 6 Nov 2026 (column H); nothing applied to AWS yet.")
        ws["A2"].font = Font(italic=True, size=9)
        ws.append([])
        ws.append(["Step", "Release", "Layer", "AWS Resource", "Description", "Change vs v2", "Repo before v3 (v2 build) -> v3 action",
                   "v3 implementation (6 Nov 2026)"])
        header_row(ws, 4)
        for step, (rel, layer, res, desc, change, envs) in enumerate(ROWS, 1):
            if env not in envs:
                continue
            status = status_of(res, change)
            ws.append([step, rel, layer, res, desc, change, status, impl_of(res, status)])
            fill = GREY if status.startswith(("WBD", "Not planned", "Manual", "Data engineers", "Backend team")) else \
                YELLOW if change == "New" else GREEN if change == "Changed" else None
            body_row(ws, fill)
        for col, w in zip("ABCDEFGH", (6, 10, 24, 46, 80, 12, 60, 60)):
            ws.column_dimensions[col].width = w
        ws.freeze_panes = "A5"

    ws = wb.create_sheet("removed_vs_v2")
    ws["A1"] = "v2 resources (built in the repo) that are not in the v3 architecture"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["#", "Layer", "Removed resource", "Replaced by / reason"])
    header_row(ws, 3)
    for i, (res, why, layer) in enumerate(REMOVED, 1):
        ws.append([i, layer, res, why])
        body_row(ws)
    for col, w in zip("ABCD", (5, 24, 60, 70)):
        ws.column_dimensions[col].width = w

    ws = wb.create_sheet("decisions")
    ws["A1"] = "v3 open points - simpler industry-standard default (implemented 6 Nov 2026; confirm with WBD)"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["#", "Question", "Proposed default", "Confirm with WBD"])
    header_row(ws, 3)
    for i, row in enumerate(DECISIONS, 1):
        ws.append([i, *row])
        body_row(ws)
    for col, w in zip("ABCD", (5, 50, 80, 24)):
        ws.column_dimensions[col].width = w
    wb.save(OUT / "aws_resource_list_3.xlsx")


# ---------------------------------------------------------------- docx
def build_docx():
    d = docx.Document()
    st = d.styles["Normal"]
    st.font.name = "Calibri"
    st.font.size = Pt(10)

    def h(text, level=1):
        d.add_heading(text, level=level)

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
            cell = t.rows[0].cells[i]
            cell.text = ""
            cell.paragraphs[0].add_run(hd).bold = True
        for r in rows:
            cells = t.add_row().cells
            for i, v in enumerate(r):
                cells[i].text = str(v)
        d.add_paragraph()

    title = d.add_heading("WBD MMM - Media Allocation & Measurement Platform", 0)
    title.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p("DevOps Implementation Plan v3 - Hybrid Lakehouse + MLOps on AWS (ECS Fargate + SageMaker + Databricks, Okta SSO, RDS PostgreSQL, SQS dispatch)", None).runs[0].bold = True
    note = p("Version 3 of wbd_mmm_ecs_final_2.docx, updated for the client architecture in wbd_Presentation_3.pptx "
             "(slide 1: auto ML activities; slide 2: optimization and explainable planning). v2 is built in the repo; "
             "this document is the v3 plan, implemented and validated offline on 6 Nov 2026 (nothing applied to AWS yet). "
             "Items marked [ASK] / [ASM] have the implemented default in section 10.")
    note.runs[0].italic = True
    note.runs[0].font.color.rgb = RGBColor(0x59, 0x59, 0x59)

    h("1. What changed vs v2")
    table(["Area", "v2 (built)", "v3 (client architecture)", "DevOps impact"], [
        ("App sign-in", "Cognito user pool federated to Okta (SAML); ALB authenticate-cognito", "SSO / Authentication - Okta (enterprise IdP), no Cognito", "Remove cognito module; ALB authenticate-oidc with an Okta OIDC app per env; secret okta/alb-client"),
        ("Database", "Aurora PostgreSQL Serverless v2 + RDS Proxy", "RDS PostgreSQL (plans, runs, allocations)", "New rds module replaces aurora; alarms, dashboard, backup, deploy snapshot change"),
        ("Run requests", "API -> Step Functions StartExecution", "API -> SQS -> Lambda message dispatcher -> Step Functions", "New sqs module + dispatcher Lambda; API role sends to SQS; queue/DLQ alarms; KMS + endpoint for SQS"),
        ("Model results", "Evaluation results in S3 and the registry", "Predictions, lift and evaluation results written back to the Gold layer", "Write-back states in model-refresh; Databricks write-back job; UC read on models/evaluation/"),
        ("Registry", "Approved models + response curves", "+ model drift monitoring", "model-monitor state machine + schedule per BU; drift Processing job; ModelDrift alarm; optional auto-refresh"),
        ("Wording", "auto ML training; API with LangGraph", "auto ML activities; API with LangGraph tools", "None"),
    ])

    h("2. Target platform")
    p("The WBD MMM application (UI + API) runs on Amazon ECS with AWS Fargate in three WBD-owned AWS accounts "
      "(Dev, Stage, Prod). Planners sign in with WBD Okta at the public Application Load Balancer (behind AWS WAF). "
      "Plans, runs and allocations live in RDS for PostgreSQL. Optimization requests are buffered in Amazon SQS and "
      "started by a Lambda dispatcher as AWS Step Functions executions that run Amazon SageMaker jobs inside the VPC. "
      "Data engineering runs on Databricks on AWS with Delta Lake on S3; SageMaker trains, evaluates and registers the "
      "models, writes predictions and lift back to the Gold layer and checks model drift.", "Decision: ")
    p("Terraform - GitHub Actions (OIDC) - Amazon ECR - Amazon ECS on Fargate + ALB - Route 53 - AWS WAF - ACM - "
      "WBD Okta (OIDC) - RDS for PostgreSQL (+ RDS Proxy) - Amazon SQS - AWS Lambda - AWS Step Functions - "
      "Amazon SageMaker (processing, training, Model Registry, drift checks) - S3 (landing, Delta Lake, training data, "
      "models, results, exports, Object Lock) - KMS - Secrets Manager + Parameter Store - Amazon EventBridge (+ Scheduler) - "
      "Databricks (Lakeflow Jobs, Unity Catalog) - Amazon API Gateway - Amazon Bedrock Guardrails - CloudWatch + CloudTrail - AWS Backup.",
      "Platform stack: ")
    p("React + TypeScript - Python / FastAPI - scikit-learn / XGBoost / LangGraph - SciPy - RDS PostgreSQL + "
      "Databricks / S3 - ECS - AWS recommended.", "Prescribed stack (WBD): ")

    h("3. Application components and runtimes")
    table(["Component", "Runs on", "What it does", "How it scales"], [
        ("mmm-ui", "ECS Fargate", "React + TypeScript web container", "CPU target tracking; Dev 1-2, Stage 2-3, Prod 2-6 tasks"),
        ("mmm-api", "ECS Fargate", "FastAPI + LangGraph tools + QA dashboard; what-if; queues runs, reads results", "CPU target tracking; Dev 1-2, Stage 2-4, Prod 3-10"),
        ("mmm-migrate", "ECS Fargate (one-off)", "Alembic DB migration before each deploy", "Once per deploy"),
        ("Run queue", "Amazon SQS (+ DLQ)", "Buffers optimization requests from 50-150 planners", "Unlimited; age and DLQ alarms"),
        ("Message dispatcher", "AWS Lambda (VPC)", "Starts executions while RUNNING < max_concurrent_runs", "Max concurrency 2"),
        ("Optimization workflow", "Step Functions (Standard)", "Async run: SageMaker job -> publisher, retries, timeouts", "One execution per run id"),
        ("Optimization & decision job", "SageMaker Processing job", "Model Summarizer, Optimizer, Simulation", "<= max_concurrent_runs at a time"),
        ("Results publisher", "AWS Lambda (VPC)", "Writes plans, runs, allocations from S3 to RDS PostgreSQL", "Per run"),
        ("Model refresh workflow", "Step Functions + EventBridge", "Lakeflow job -> train -> evaluate -> register -> write-back", "Scheduled / manual / app-triggered"),
        ("Model monitor workflow", "Step Functions + Scheduler", "Monitor export -> drift job -> alarm / optional refresh", "Daily per BU"),
        ("Lakeflow Jobs", "Databricks on AWS", "Ingestion, Bronze, Silver, Gold, Feature Export, write-back", "Databricks job clusters"),
        ("Training, evaluation, drift", "SageMaker training / processing jobs", "Multi-stage models; baseline, channel lift, title adjustment; drift", "Per refresh / check"),
        ("LLM gateway (Release 2)", "Amazon API Gateway (+ Lambda)", "OpenAI / Anthropic / Google models; Bedrock Guardrails", "Stage throttling; BU quotas in the API"),
    ])

    h("4. The two flows")
    h("4.1 Auto ML activities (slide 1)", 2)
    bullets([
        "Scheduled refresh (EventBridge Scheduler), manual or application-triggered refresh -> EventBridge -> Step Functions (schedule / manual, wait / retry).",
        "Step Functions runs Databricks Lakeflow Jobs: ingestion from S3 into the Databricks catalog -> Bronze (raw) -> Silver (cleansed, validated) -> Gold (per-BU modeling tables, adstock & saturation) -> Feature Export (plans, runs, allocations).",
        "Raw data landing comes from S3 (3+ years of historical inventory). Delta Lake storage for Bronze/Silver/Gold is backed by S3.",
        "Training data: immutable Parquet + metadata in S3 -> SageMaker modeling in the VPC: training (multi-stage) -> evaluation (baseline -> channel lift -> title adjustment) -> model registration (PendingManualApproval).",
        "NEW: Step Functions starts the Databricks write-back job, which merges the model predictions, lift and evaluation results into the corresponding per-BU Gold tables.",
        "A named WBD approver approves the version (model-governance.yml); the approved response curves and the drift baseline are published to S3.",
        "NEW: model drift monitoring - per BU on a schedule, a monitor export of the latest Gold features is compared with the approved baseline by a SageMaker drift job; drift above the threshold alarms and (optionally) starts a refresh.",
    ])
    h("4.2 Optimization and explainable planning (slide 2)", 2)
    bullets([
        "Planner uploads inventory, chooses an objective, runs and compares -> DNS / WAF -> ALB (HTTPS, public entry).",
        "NEW: the ALB signs the planner in with WBD Okta (OIDC, MFA in Okta); the API reads the Okta groups for BU + role.",
        "ECS UI -> ECS API (FastAPI with LangGraph tools and QA dashboard) <-> NEW RDS PostgreSQL (plans, runs, allocations). What-if runs in the API on the approved curves.",
        "NEW: for a full run the API writes the input to S3, stores the run as QUEUED and sends a message to SQS; the Lambda message dispatcher starts the Step Functions execution when capacity is free.",
        "Step Functions (async) -> SageMaker job for optimization & decision (Model Summarizer, Optimizer, Simulation) reading the approved model + response curves -> S3 outputs (full run evidence) -> Lambda results publisher -> RDS PostgreSQL.",
        "API -> Amazon API Gateway -> OpenAI / Anthropic / Google models, with Amazon Bedrock Guardrails (Release 2).",
        "Sized for 50-150 planners working at the same time in planning seasons; the queue absorbs bursts within the SageMaker quota.",
    ])

    h("5. Deployment approach - Flywheel pattern on AWS (updated)")
    table(["Flywheel (Azure)", "WBD MMM v3 (AWS)"], [
        ("Container Apps Environment", "ECS cluster (Fargate)"),
        ("Container App + revision", "ECS service (ui, api) + task definition revision"),
        ("Container App Job", "SageMaker job via SQS -> dispatcher -> Step Functions (optimization); ECS one-off task (migration)"),
        ("Built-in ingress + managed certificate", "Public ALB + ACM + regional WAF; Route 53"),
        ("Entra ID login", "WBD Okta (OIDC at the ALB)"),
        ("Azure Container Registry", "Amazon ECR (per env, digest promotion)"),
        ("Key Vault", "Secrets Manager / Parameter Store"),
        ("Service Bus / Storage queue", "Amazon SQS (+ DLQ)"),
        ("Log Analytics", "CloudWatch Logs + Container Insights + Application Signals"),
        ("PostgreSQL Flexible Server", "RDS for PostgreSQL (+ RDS Proxy)"),
        ("Storage account / Blob", "Amazon S3"),
        ("Azure ML / model registry / model monitoring", "SageMaker training + Model Registry + drift Processing jobs"),
        ("Recovery / Backup vault", "AWS Backup"),
        ("azure/login (OIDC)", "aws-actions/configure-aws-credentials (OIDC)"),
        ("Pre-deploy pg_dump", "RDS DB snapshot before Prod migrations"),
    ])

    h("6. Alternatives to confirm")
    table(["#", "Alternative", "Why"], [
        ("A", "App-level OIDC (PKCE in the UI, JWT check in the API) instead of ALB authenticate-oidc", "No client secret at the ALB; but auth code in both apps"),
        ("B", "RDS Multi-AZ DB cluster (two readable standbys) instead of a Multi-AZ DB instance", "Faster failover and read scaling; higher cost"),
        ("C", "EventBridge Pipes (SQS -> Step Functions) instead of the dispatcher Lambda", "No code; but no concurrency gate against the SageMaker quota"),
        ("D", "SQS FIFO with message groups per BU", "Per-BU ordering / fairness; lower throughput, more complex"),
        ("E", "Automatic refresh on drift", "Fresher models; risk of retrain loops on noisy data - alert-only by default"),
        ("F", "SageMaker Model Monitor with a batch-transform step", "Managed drift reports; needs a batch transform the design does not have"),
        ("G", "Anthropic through Amazon Bedrock instead of the public API", "Keeps that traffic inside AWS"),
    ])

    h("7. Environments")
    table(["Environment", "AWS account", "Use", "Size", "Approves changes"], [
        ("Dev", "wbd-mmm-dev", "Daily development, automated tests", "Small", "Automatic"),
        ("Stage", "wbd-mmm-stage", "Release testing, UAT, parallel run, performance and security tests", "Close to Prod", "EY lead"),
        ("Prod", "wbd-mmm-prod", "Live use by WBD planners (50-150 concurrent)", "Full, HA", "WBD approver + change ticket"),
    ])
    h("7.1 Environment differences", 2)
    table(["Setting", "Dev", "Stage", "Prod"], [
        ("Availability Zones", "2", "3", "3"),
        ("ECS UI / API tasks", "1-2 / 1-2", "2-3 / 2-4", "2-6 / 3-10"),
        ("RDS PostgreSQL [ASM]", "db.t4g.medium, single-AZ", "db.r6g.large, Multi-AZ", "db.r6g.xlarge, Multi-AZ, deletion protection"),
        ("max_concurrent_runs [ASM]", "5", "20", "50 (<= SageMaker quota)"),
        ("SageMaker instance types", "ml.m5.xlarge / ml.m5.2xlarge", "Prod-like for performance tests", "Sized from the load test"),
        ("Backups", "PITR 7 d", "PITR 14 d + AWS Backup + restore tests", "PITR 35 d, vault lock, cross-region if approved"),
        ("Log retention", "30 days", "90 days", "365 days (+ Splunk)"),
        ("Data allowed", "Synthetic / masked", "Approved prod-like clone", "Production"),
        ("Deployment approval", "Automatic", "EY lead", "WBD approver + change ticket"),
    ])

    h("8. Stages at a glance")
    table(["Stage", "Name", "Main output (v3 change)"], [
        ("0", "Access", "Logins to GitHub, AWS, Databricks, Okta admin contact"),
        ("1", "Questions for the client", "v3 questions (section 10)"),
        ("2", "Design and approval", "Approved v3 design pack"),
        ("3", "Account foundation", "KMS adds sqs; deploy role RDS snapshot"),
        ("4", "Networking", "SQS endpoint; RDS security group"),
        ("5", "Security baseline + identity", "Okta OIDC app per env, okta/alb-client secret; Cognito removed"),
        ("6", "Data & storage", "RDS PostgreSQL + Proxy (replaces Aurora)"),
        ("7", "ECS on Fargate", "API role sends to SQS; Okta env"),
        ("8", "Docker", "Unchanged images"),
        ("9", "Optimization engine", "SQS + DLQ + dispatcher Lambda in front of Step Functions"),
        ("10", "Data & ML platform", "Write-back job; model-monitor (drift) state machine"),
        ("11", "CI/CD", "RDS snapshot; dry run through the queue; Okta smoke test"),
        ("12", "Front door and login", "ALB authenticate-oidc (Okta)"),
        ("13", "Logging and monitoring", "RDS, SQS, dispatcher, drift alarms; dashboards"),
        ("14", "Backup and DR", "RDS instance in AWS Backup"),
        ("15", "Testing and Release 1 go-live", "Queue load test, RDS failover, Okta login, drift alarm test"),
        ("16", "Release 2 - GenAI", "Unchanged"),
        ("17", "Handover and operations", "okta-outage, model-drift, write-back-failed runbooks"),
    ])

    h("9. Stages")
    stages = [
        ("Stage 0 - Access", ["Access to GitHub, AWS (SSO + CLI), Databricks workspace, SageMaker, Splunk, CloudWatch.",
                              "Contacts: WBD Cloud Platform, Network, Identity (Okta), Databricks admins, Data Science lead, InfoSec, CAB."]),
        ("Stage 1 - Questions for the client", ["All v2 questions except Cognito, plus the v3 questions in section 10 (Okta OIDC, RDS sizing, run concurrency, write-back, drift)."]),
        ("Stage 2 - Design and approval", ["Deployment diagram from wbd_Presentation_3.pptx with network detail.",
                                           "ADRs: Okta at the ALB, RDS PostgreSQL, SQS + dispatcher, write-back to Gold, drift monitoring as Processing jobs."]),
        ("Stage 3 - Account foundation", ["KMS keys per purpose incl. sqs; permission boundary on the new dispatcher and model-monitor roles; deploy role with RDS snapshot actions."]),
        ("Stage 4 - Networking", ["Unchanged subnets; add the SQS interface endpoint; RDS security group (from RDS Proxy only); dispatcher reuses the Lambda SG; ALB egress to Okta."]),
        ("Stage 5 - Security baseline and identity", ["App users: WBD Okta OIDC app per environment (MFA, groups claim) -> ALB authenticate-oidc -> API RBAC -> PostgreSQL RLS per BU.",
                                                       "Secret mmm/<env>/okta/alb-client; SSM okta/issuer and optimization/max_concurrent_runs; Cognito resources and cognito/* parameters removed."]),
        ("Stage 6 - Data & storage", ["RDS for PostgreSQL 16.x: IAM auth, force_ssl, pgaudit, Performance Insights, Enhanced Monitoring, Multi-AZ in stg/prd, deletion protection in prod; RDS Proxy for ECS + publisher.",
                                      "S3 buckets unchanged; new prefixes models/baseline, models/monitoring, models/evaluation/.../predictions + lift, lakehouse/monitoring."]),
        ("Stage 7 - ECS on Fargate", ["API task role: sqs:SendMessage on the run queue (no StartExecution); env OPTIMIZATION_QUEUE_URL, OKTA_ISSUER; UI LOGOUT_URL from Okta."]),
        ("Stage 8 - Docker", ["Unchanged: mmm/ui, mmm/api, mmm/sagemaker-optimizer, mmm/sagemaker-training (training image adds the drift argument)."]),
        ("Stage 9 - Optimization engine", ["SQS Standard queue + DLQ (KMS, TLS-only policy); dispatcher Lambda with event source mapping (max concurrency 2) starts executions while RUNNING < max_concurrent_runs; execution name = run_id (idempotent).",
                                           "Optimization state machine, SageMaker job and results publisher unchanged (publisher writes to RDS)."]),
        ("Stage 10 - Data & ML platform", ["Model refresh adds write-back states (Databricks write-back job -> Gold).",
                                           "Model monitor state machine + schedule per BU: monitor export -> drift job -> ModelDrift metric + alarm -> optional mmm.refresh.",
                                           "model-governance.yml publishes curves + baseline and writes approval.json."]),
        ("Stage 11 - CI/CD with GitHub Actions", ["deploy.yml: RDS snapshot before prod migrations; optimization dry run through the queue in dev/staging; Okta redirect smoke test. GitHub variables DB_INSTANCE_ID and OPTIMIZATION_QUEUE_URL."]),
        ("Stage 12 - Front door and login", ["Route 53 / WBD DNS, ACM, regional WAF unchanged; ALB authenticate-oidc with Okta; /api/* 401 when not signed in.",
                                             "Done when: Okta login + MFA works, unauthenticated users are redirected, groups reach the API, one BU cannot see another BU's data."]),
        ("Stage 13 - Logging and monitoring", ["RDS CPU / free storage / connections / latency; SQS oldest message age; DLQ not empty; dispatcher errors; ModelDrift per BU; model-monitor failed; existing alarms unchanged."]),
        ("Stage 14 - Backup and DR", ["RDS automated backups + AWS Backup (vault lock in prod, cross-region if approved); Multi-AZ failover test in staging."]),
        ("Stage 15 - Testing and Release 1 go-live", ["Performance test with 50 / 100 / 150 planners incl. queue wait; SageMaker quota >= max_concurrent_runs; DAST and pen test; RDS failover; drift alarm test; parallel run and UAT; CAB; cutover."]),
        ("Stage 16 - Release 2 GenAI", ["Unchanged: private API Gateway + proxy Lambda to OpenAI / Anthropic / Google, Bedrock Guardrails on every call, behind enable_genai."]),
        ("Stage 17 - Handover", ["Runbooks updated: okta-outage (replaces cognito-idp-outage), db-restore (RDS), optimization-run-failed (+ queue / DLQ redrive), scale-planning-season (+ max_concurrent_runs), rotation (+ Okta secret); new model-drift and write-back-failed."]),
    ]
    for name, items in stages:
        h(name, 2)
        bullets(items)

    h("10. Questions for WBD (v3) and the proposed default")
    p("Each open point has a simpler industry-standard default, implemented on 6 Nov 2026; "
      "the last column says what WBD still has to confirm.")
    table(["#", "Question", "Proposed default", "Confirm"],
          [(str(i), *row) for i, row in enumerate(DECISIONS, 1)])

    h("10a. Impact on the current code (v2 build)")
    bullets([
        "Remove: modules/cognito, modules/aurora, Cognito variables / outputs / SSM parameters, Aurora alarms and dashboard, AURORA_CLUSTER_ID.",
        "Add: modules/rds (DB instance + parameter group + Proxy), modules/run-queue (queue + DLQ + dispatcher Lambda + alarms), "
        "write-back states, model-monitor state machine + schedules, drift / queue / RDS alarms.",
        "Change: modules/alb (authenticate-oidc), network (sqs endpoint, RDS SG), kms (sqs), monitoring, backup, databricks-access; "
        "frontdoor.tf, main.tf, ecs.tf, optimization.tf, data.tf, outputs, variables, tfvars, ecs/<env>/*.json; deploy.yml, "
        "model-governance.yml, scripts (dry run, platform check, smoke, setup-github), data/README.md, data/model-thresholds.yaml, docs and runbooks.",
        "Unchanged: bootstrap, ECR, S3 bucket set, ECS cluster/services, WAF, optimization state machine definition, SageMaker roles, "
        "publisher Lambda, model-refresh core, registry + governance flow, GenAI, log shipping, app CI workflows, terraform.yml, databricks.yml.",
        "Status: implemented 6 Nov 2026 and validated offline (fmt, validate of 24 modules, tflint, Checkov 0 failed, actionlint, "
        "shellcheck, secret scan, thresholds check). Mock plan (resources to add, default / all features on): dev 311 / 459, "
        "staging 326 / 476, prod 326 / 478. Nothing applied to AWS yet.",
        "Built differently from this plan (simpler): one modules/run-queue holds queue, DLQ, dispatcher Lambda and its alarms "
        "(instead of modules/sqs + modules/run-dispatcher); the Okta secret name is fixed (mmm/<env>/okta/alb-client, no "
        "okta_client_secret_name variable) and okta_sign_in_enabled keeps the ALB at 503 until the secret is in place; "
        "the drift check runs daily (cron(0 7 * * ? *)) instead of weekly; SMOKE_CHECK_LOGIN follows okta_sign_in_enabled.",
    ])

    h("11. Risks")
    table(["Risk", "Mitigation"], [
        ("Okta OIDC client secret sits in the ALB configuration and the Terraform state", "Secrets Manager source, encrypted state bucket with restricted access, rotation runbook; or app-level PKCE (alternative A)"),
        ("RDS instance scales less smoothly than Aurora Serverless in planning seasons", "Size from the load test, storage autoscaling, RDS Proxy pooling, planned class change before the season"),
        ("Queue backlog in peak season (150 planners)", "max_concurrent_runs aligned with the SageMaker quota, oldest-message alarm, queue wait shown in the UI"),
        ("Dispatcher bug stops all runs", "Small DevOps-owned code with tests; DLQ + alarms; runbook to start executions by hand"),
        ("Write-back mixes candidate and approved results in Gold", "Key by refresh_id + version and carry approval status (approval.json)"),
        ("Drift alarms without agreed thresholds create noise", "Schedule off until data science + WBD agree thresholds; alert-only by default"),
        ("External LLM providers move data outside AWS", "Unchanged: written approval, guardrails on every call, GenAI off until Release 2"),
    ])

    h("12. AWS resource list summary (details in aws_resource_list_3.xlsx)")
    table(["Layer", "Resources", "Dev", "Stage", "Prod", "New in v3", "Changed"], [
        (layer,
         sum(1 for r in ROWS if r[1] == layer),
         sum(1 for r in ROWS if r[1] == layer and "dev" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and "staging" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and "prod" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and r[4] == "New"),
         sum(1 for r in ROWS if r[1] == layer and r[4] == "Changed"))
        for layer in dict.fromkeys(r[1] for r in ROWS)
    ])
    d.save(OUT / "wbd_mmm_ecs_final_3.docx")


build_xlsx()
build_docx()
print("rows:", len(ROWS), "removed:", len(REMOVED), "decisions:", len(DECISIONS))

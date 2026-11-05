"""Builds aws_resource_list_2.xlsx and wbd_mmm_ecs_final_2.docx (v2 architecture)."""
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

# (release, layer, resource, description, change vs v1, environments)
ROWS = [
    # 1. Account foundation
    (R1, "1. Account foundation", "AWS account", "Separate WBD-owned AWS account for the environment.", "Same", ALL),
    (R1, "1. Account foundation", "Service Control Policy (region lock)", "Blocks AWS regions that WBD has not approved.", "Same", ALL),
    (R1, "1. Account foundation", "IAM Identity Center permission sets", "SSO roles for engineers (ReadOnly/Developer/DevOps/Security/BreakGlass); no IAM users.", "Same", ALL),
    (R1, "1. Account foundation", "AWS CloudTrail", "Records every API call for audit (shown under Operations on the slides).", "Same", ALL),
    (R1, "1. Account foundation", "Amazon GuardDuty", "Detects threats and suspicious activity.", "Same", ALL),
    (R1, "1. Account foundation", "AWS Security Hub", "Shows all security findings in one place.", "Same", ALL),
    (R1, "1. Account foundation", "AWS Config", "Tracks resource settings and flags non-compliant ones.", "Same", ALL),
    (R1, "1. Account foundation", "Amazon Inspector", "Scans ECR images (api, ui, SageMaker optimizer/training images).", "Changed", ALL),
    (R1, "1. Account foundation", "IAM Access Analyzer", "Finds resources shared outside the account by mistake.", "Same", ALL),
    (R1, "1. Account foundation", "S3 Block Public Access (account level)", "Stops any S3 bucket from being made public.", "Same", ALL),
    (R1, "1. Account foundation", "EBS encryption by default", "Makes every new disk encrypted automatically.", "Same", ALL),
    (R1, "1. Account foundation", "KMS keys", "Keys per purpose: state, ECR, Aurora, S3 (+ per BU), logs, secrets, SageMaker (new); no SQS/Redis key.", "Changed", ALL),
    (R1, "1. Account foundation", "KMS key policies", "Control which roles and AWS services can use each key.", "Same", ALL),
    (R1, "1. Account foundation", "S3 bucket - Terraform state", "Stores Terraform state (versioned, encrypted, S3 lock file).", "Same", ALL),
    (R1, "1. Account foundation", "DynamoDB table - state lock (optional)", "Optional; S3 native lock file is the default.", "Same", ALL),
    (R1, "1. Account foundation", "IAM permission boundary", "Attached to every Terraform-created role, now incl. SageMaker, Step Functions, Lambda and Scheduler roles.", "Changed", ALL),
    (R1, "1. Account foundation", "IAM OIDC identity provider (GitHub)", "Lets GitHub Actions log in to AWS without stored keys.", "Same", ALL),
    (R1, "1. Account foundation", "IAM roles - GitHub Actions", "gha-plan, gha-apply, gha-deploy (ECS api+ui, SSM image tags), gha-ecr-push/read, model-approval role.", "Changed", ALL),
    (R1, "1. Account foundation", "AWS Budgets", "Alerts when spend reaches 50/80/100% of budget.", "Same", ALL),
    (R1, "1. Account foundation", "AWS Budgets - SageMaker cost", "Separate budget for SageMaker training and optimization jobs.", "New", ALL),
    (R1, "1. Account foundation", "Cost Anomaly Detection monitor", "Alerts on unexpected spend increases.", "Same", ALL),
    (R1, "1. Account foundation", "Amazon Macie (optional)", "Finds sensitive data stored in S3 buckets.", "Same", ALL),
    # 2. Networking
    (R1, "2. Networking", "VPC", "Private network for the environment (/19).", "Same", ALL),
    (R1, "2. Networking", "Public subnets", "Hold the public ALB (public entry) and NAT gateways.", "Same", ALL),
    (R1, "2. Networking", "Private-app subnets", "Hold ECS tasks (ui, api), the results-publisher Lambda and SageMaker job ENIs.", "Changed", ALL),
    (R1, "2. Networking", "Private-data subnets", "Hold Aurora PostgreSQL with no internet access.", "Changed", ALL),
    (R1, "2. Networking", "Private-endpoint subnets", "Hold VPC interface endpoints (no MWAA any more).", "Changed", ALL),
    (R1, "2. Networking", "Internet Gateway", "Connects public subnets to the internet.", "Same", ALL),
    (R1, "2. Networking", "Elastic IP (for NAT)", "Fixed public IP used by each NAT gateway.", "Same", ALL),
    (R1, "2. Networking", "NAT Gateway", "Outbound only; also the allow-listed egress to external LLM providers in Release 2 [ASK].", "Changed", ALL),
    (R1, "2. Networking", "Route tables + associations", "Public -> IGW, app -> NAT, data/endpoint -> no internet.", "Same", ALL),
    (R1, "2. Networking", "Security group - VPC endpoints", "Allows HTTPS (443) from inside the VPC.", "Same", ALL),
    (R1, "2. Networking", "VPC gateway endpoints (S3, DynamoDB)", "Private, free access to S3 and DynamoDB.", "Same", ALL),
    (R1, "2. Networking", "VPC interface endpoints", "ECR api/dkr, STS, Secrets Manager, SSM, SSM Messages, KMS, Logs, Monitoring, X-Ray + NEW Step Functions (states), SageMaker API, SageMaker Runtime (if endpoints); SQS removed.", "Changed", ALL),
    (R1, "2. Networking", "Security group - ALB", "HTTPS from the internet or WBD ranges [ASK]; no CloudFront prefix list any more.", "Changed", ALL),
    (R1, "2. Networking", "Security group - ECS ui service", "Allows traffic to UI tasks only from the ALB.", "New", ALL),
    (R1, "2. Networking", "Security group - ECS api service", "Allows traffic to API tasks only from the ALB.", "Same", ALL),
    (R1, "2. Networking", "Security group - SageMaker jobs", "No inbound; outbound 443 to VPC endpoints and the S3 prefix list.", "New", ALL),
    (R1, "2. Networking", "Security group - Lambda results publisher", "No inbound; outbound to RDS Proxy and VPC endpoints.", "New", ALL),
    (R1, "2. Networking", "Security group - RDS Proxy", "Allows DB connections only from API tasks, the migrate task and the results publisher.", "Changed", ALL),
    (R1, "2. Networking", "Security group - Aurora", "Allows DB traffic only from RDS Proxy.", "Changed", ALL),
    (R1, "2. Networking", "S3 bucket - logs", "Stores ALB access logs and S3 access logs (no CloudFront logs).", "Changed", ALL),
    (R1, "2. Networking", "VPC Flow Logs", "Records network traffic for security checks.", "Same", ALL),
    (R1, "2. Networking", "Transit Gateway attachment (optional)", "Connects the VPC to WBD's network (VDI, Splunk, Databricks).", "Same", ALL),
    (R1, "2. Networking", "Databricks PrivateLink endpoints", "Workspace (front-end/REST) + secure cluster connectivity relay.", "Changed", ALL),
    (R1, "2. Networking", "Route 53 private hosted zone (Databricks PrivateLink)", "Private DNS so tasks resolve Databricks names to the private endpoint.", "Same", ALL),
    (R1, "2. Networking", "Route 53 Resolver outbound endpoint + rules (optional)", "Resolves WBD internal names over the Transit Gateway.", "Same", ALL),
    (R1, "2. Networking", "Databricks customer-managed VPC subnets + SG (optional)", "Only if Databricks classic compute runs in the MMM account ('Private VPC compute') [ASK].", "New", ALL),
    (R1, "2. Networking", "EC2 key pair", "Not needed - no servers to log in to.", "Same", ALL),
    # 3. Container registry
    (R1, "3. Container registry", "ECR repositories", "One registry per environment: mmm/api, mmm/ui, mmm/sagemaker-optimizer, mmm/sagemaker-training [ASM].", "Changed", ALL),
    (R1, "3. Container registry", "ECR lifecycle policy", "Deletes old untagged images to save cost.", "Same", ALL),
    (R1, "3. Container registry", "ECR tag immutability + enhanced scanning", "Stops tags being overwritten and scans every image.", "Same", ALL),
    (R1, "3. Container registry", "Image promotion (pipeline step)", "Same digest copied dev -> staging -> prod on rc/release tags, incl. SageMaker images.", "Same", ALL),
    # 4. Security & secrets
    (R1, "4. Security & secrets", "Secrets Manager secrets", "DB users, Databricks OAuth service principal, Splunk, third parties; Redis token and origin secret removed.", "Changed", ALL),
    (R1, "4. Security & secrets", "SSM Parameter Store parameters", "Cognito IDs, Databricks host/job IDs, SageMaker image tags, state machine ARNs, feature flags.", "Changed", ALL),
    # 5. Identity
    (R1, "5. Identity & login", "Amazon Cognito user pool", "One per environment; app user directory and token issuer.", "New", ALL),
    (R1, "5. Identity & login", "Cognito identity provider (WBD Okta, OIDC/SAML)", "Federates login to the WBD enterprise IdP (MFA, groups) [ASK].", "New", ALL),
    (R1, "5. Identity & login", "Cognito app client + hosted domain", "UI client (Auth Code + PKCE) used by the ALB authenticate-cognito action / UI.", "New", ALL),
    (R1, "5. Identity & login", "Cognito resource server + groups", "API scopes and BU/role groups mapped from IdP claims (RBAC).", "New", ALL),
    # 6. Data & storage
    (R1, "6. Data & storage", "S3 bucket - landing", "Raw source data by feed and date; 3+ years history.", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - lakehouse (Delta Lake)", "Bronze / Silver / Gold Delta tables (Unity Catalog external location).", "New", ALL),
    (R1, "6. Data & storage", "S3 bucket - training data", "Immutable Parquet + metadata exported from Gold [ASK Object Lock].", "New", ALL),
    (R1, "6. Data & storage", "S3 bucket - models", "SageMaker model artifacts and approved MMM response curves.", "New", ALL),
    (R1, "6. Data & storage", "S3 bucket - outputs", "Full run evidence of every optimization / simulation (replaces 'results').", "Changed", ALL),
    (R1, "6. Data & storage", "S3 bucket - approved (Object Lock)", "Approved scenarios that cannot be changed.", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - exports", "Excel exports, auto-deleted after 30 days.", "Same", ALL),
    (R1, "6. Data & storage", "S3 bucket - SageMaker staging", "Job code and temporary inputs, auto-deleted after 30 days [ASM].", "New", ALL),
    (R1, "6. Data & storage", "S3 bucket policies", "HTTPS-only and deny unencrypted uploads on every bucket.", "Same", ALL),
    (R1, "6. Data & storage", "S3 EventBridge notifications (landing bucket)", "Sends 'new file' events to EventBridge (optional refresh trigger).", "Same", ALL),
    (R1, "6. Data & storage", "IAM role - Databricks Unity Catalog", "Lets Databricks read/write landing, lakehouse and training-data buckets.", "Changed", ALL),
    (R1, "6. Data & storage", "KMS keys per business unit (S3)", "BU data isolation for lakehouse and training data.", "Same", ALL),
    (R1, "6. Data & storage", "DB subnet group", "Private-data subnets for Aurora.", "Same", ALL),
    (R1, "6. Data & storage", "Aurora cluster + DB parameter groups", "force_ssl, pgaudit, logging settings.", "Changed", ALL),
    (R1, "6. Data & storage", "IAM role - RDS Enhanced Monitoring", "OS metrics; Performance Insights on.", "Same", ALL),
    (R1, "6. Data & storage", "Aurora PostgreSQL cluster", "Plans, runs, allocations, audit; writer + reader (Multi-AZ) in stg/prd. Replaces RDS PostgreSQL [ASK].", "New", ALL),
    (R1, "6. Data & storage", "Aurora master password in Secrets Manager (auto-rotation)", "RDS creates and rotates the admin password.", "Same", ALL),
    (R1, "6. Data & storage", "IAM role - RDS Proxy", "Lets RDS Proxy read the DB user secrets.", "Same", ALL),
    (R1, "6. Data & storage", "RDS Proxy", "Pools connections from ECS and Lambda to Aurora (IAM auth, TLS) [ASK].", "Changed", ALL),
    # 7. ECS compute
    (R1, "7. ECS compute", "ECS cluster (Fargate)", "Serverless container cluster with Container Insights enhanced.", "Same", ALL),
    (R1, "7. ECS compute", "Service Quotas increase (Fargate vCPU)", "Raise Fargate vCPU limit before load tests and go-live.", "Same", STG_PRD),
    (R1, "7. ECS compute", "IAM role - ECS task execution", "Pulls images, writes logs and reads listed secrets.", "Same", ALL),
    (R1, "7. ECS compute", "IAM roles - ECS task roles", "One role per service: api, ui, migrate.", "Changed", ALL),
    (R1, "7. ECS compute", "CloudWatch log groups (per service)", "Logs per ECS service with retention and KMS.", "Same", ALL),
    (R1, "7. ECS compute", "CloudWatch Logs data protection policy (optional)", "Masks personal data if it appears in logs.", "Same", ALL),
    (R1, "7. ECS compute", "ECS task definition - migrate", "One-off task that runs DB migrations before each deploy.", "Same", ALL),
    (R1, "7. ECS compute", "ECS task definition - api", "FastAPI API with LangGraph and QA dashboard.", "Changed", ALL),
    (R1, "7. ECS compute", "ECS task definition - ui", "React + TypeScript web container (nginx, non-root).", "New", ALL),
    (R1, "7. ECS compute", "ACM certificate (project region)", "The only certificate: app name on the public ALB.", "Changed", ALL),
    (R1, "7. ECS compute", "Application Load Balancer (public entry)", "User-facing HTTPS entry; routes /api/* to API and /* to UI.", "Changed", ALL),
    (R1, "7. ECS compute", "ALB target groups (ip) - ui and api", "Health checks /healthz (UI) and /api/health (API) [ASK].", "Changed", ALL),
    (R1, "7. ECS compute", "ALB HTTPS listener + rules", "Path routing + authenticate-cognito action; HTTP -> HTTPS redirect.", "Changed", ALL),
    (R1, "7. ECS compute", "ECS service - mmm-api", "API tasks behind the ALB (circuit breaker on).", "Same", ALL),
    (R1, "7. ECS compute", "ECS service - mmm-ui", "UI web tasks behind the ALB (circuit breaker on).", "New", ALL),
    (R1, "7. ECS compute", "Application Auto Scaling policies", "API on CPU/requests, UI on CPU (no SQS backlog scaling).", "Changed", ALL),
    # 8. Edge
    (R1, "8. Edge & front door", "AWS WAF web ACL (regional, on the ALB)", "Managed rules + rate limit in front of the ALB (replaces CloudFront WAF).", "Changed", ALL),
    (R1, "8. Edge & front door", "WAF logging configuration", "WAF logs to aws-waf-logs-* log group (-> Splunk).", "Same", ALL),
    (R1, "8. Edge & front door", "Route 53 DNS records", "mmm-dev / mmm-stg / mmm -> ALB (WBD DNS creates).", "Changed", ALL),
    # 9. Optimization engine
    (R1, "9. Optimization engine", "IAM role - SageMaker optimization jobs", "Reads models + response curves, writes outputs, VPC + KMS.", "New", ALL),
    (R1, "9. Optimization engine", "SageMaker model package groups (per BU)", "Registry entries the optimizer reads (latest Approved version).", "New", ALL),
    (R1, "9. Optimization engine", "Step Functions state machine - optimization", "Async execution: SageMaker job (summarizer, optimizer, simulation) -> publish; retries, timeouts.", "New", ALL),
    (R1, "9. Optimization engine", "IAM role + log group - optimization state machine", "Permissions to run SageMaker jobs and invoke the publisher; logs + X-Ray.", "New", ALL),
    (R1, "9. Optimization engine", "SageMaker job - optimization & decision (runtime)", "Processing/training job from mmm/sagemaker-optimizer; runs in the VPC.", "New", ALL),
    (R1, "9. Optimization engine", "Lambda function - results publisher", "Writes plans, runs and allocations from S3 outputs to Aurora.", "New", ALL),
    (R1, "9. Optimization engine", "IAM role + log group + DLQ - results publisher", "Least-privilege role, logs and failed-event destination.", "New", ALL),
    (R1, "9. Optimization engine", "SageMaker service quotas + warm pools", "Instance quotas for 50-150 concurrent planners; warm pools for faster starts.", "New", ALL),
    (R1, "9. Optimization engine", "SageMaker endpoint - simulation (optional)", "Real-time/serverless endpoint if what-if must answer in ~10 s [ASK].", "New", ALL),
    # 10. Data & ML training platform
    (R1, "10. Data & ML platform", "EventBridge Scheduler - scheduled refresh", "Starts the model-refresh state machine on schedule.", "New", ALL),
    (R1, "10. Data & ML platform", "EventBridge rule - manual / app-triggered refresh", "mmm.refresh events from the API or operators (+ optional S3 arrival).", "New", ALL),
    (R1, "10. Data & ML platform", "EventBridge connection (Databricks OAuth)", "Credentials for the Step Functions HTTP Task that runs Lakeflow jobs.", "New", ALL),
    (R1, "10. Data & ML platform", "Step Functions state machine - model refresh", "Lakeflow job -> publish Parquet -> train -> evaluate -> register; wait/retry.", "New", ALL),
    (R1, "10. Data & ML platform", "IAM role + log group - model refresh state machine", "Permissions for HTTP Task, SageMaker jobs, S3, registry; logs.", "New", ALL),
    (R1, "10. Data & ML platform", "Databricks Lakeflow Jobs", "Ingestion -> Bronze -> Silver -> Gold -> Feature Export (deployed by bundles; WBD Databricks).", "New", ALL),
    (R1, "10. Data & ML platform", "Unity Catalog storage credential + external locations", "Delta Lake tables on the lakehouse bucket; lineage on.", "New", ALL),
    (R1, "10. Data & ML platform", "IAM roles - SageMaker training + evaluation", "Read training data, write models, register packages, VPC + KMS.", "New", ALL),
    (R1, "10. Data & ML platform", "SageMaker training job (runtime)", "Trains/tunes multi-stage models from the Parquet files.", "New", ALL),
    (R1, "10. Data & ML platform", "SageMaker processing job - evaluation (runtime)", "Baseline -> channel lift -> title adjustment vs thresholds.", "New", ALL),
    (R1, "10. Data & ML platform", "SageMaker Model Registry - model versions", "Approved model versioned and registered (PendingManualApproval -> Approved).", "New", ALL),
    (R1, "10. Data & ML platform", "EventBridge rule - model package state change", "Notifies approvers / starts model-governance workflow.", "New", ALL),
    (R1, "10. Data & ML platform", "SageMaker Studio domain (optional)", "Only if data scientists need Studio in the account [ASK].", "New", ALL),
    # 11. Monitoring
    (R1, "11. Monitoring & logging", "SNS topic (alerts)", "Alarm notifications to email/Teams.", "Same", ALL),
    (R1, "11. Monitoring & logging", "AWS Chatbot / Q Developer in chat apps (optional)", "Alerts to Microsoft Teams.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch Container Insights", "Health and usage of ECS services and tasks.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch Application Signals", "API latency, errors and traces.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch alarms", "ALB/API, Step Functions, SageMaker jobs, Lambda, Aurora, pipeline freshness, model thresholds.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "EventBridge rules -> SNS", "GuardDuty High, ECS deployment failure, Step Functions failed, SageMaker job failed.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch dashboards", "Platform, API/UI, optimization runs, training pipeline, Aurora, cost.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "IAM role + S3 backup bucket - Firehose", "Firehose to Splunk + failed-delivery bucket [ASK Splunk].", "Same", ALL),
    (R1, "11. Monitoring & logging", "Kinesis Data Firehose (to Splunk)", "Delivers logs into WBD Splunk [ASK].", "Same", ALL),
    (R1, "11. Monitoring & logging", "IAM role - CloudWatch Logs subscription", "Lets CloudWatch Logs send to Firehose.", "Same", ALL),
    (R1, "11. Monitoring & logging", "CloudWatch Logs subscription filters", "ECS, Lambda, Step Functions, SageMaker, WAF logs -> Firehose.", "Changed", ALL),
    (R1, "11. Monitoring & logging", "S3 bucket + IAM role - Synthetics (optional)", "Canary results and permissions.", "Same", STG_PRD),
    (R1, "11. Monitoring & logging", "CloudWatch Synthetics canary (optional)", "Logs in and checks the app every few minutes.", "Same", STG_PRD),
    # 12. Backup
    (R1, "12. Backup & DR", "Aurora automated backups / PITR", "Restore the cluster to any point in time (7/14/35 days).", "Changed", ALL),
    (R1, "12. Backup & DR", "AWS Backup vault", "Encrypted store for backups (vault lock in prod).", "Same", STG_PRD),
    (R1, "12. Backup & DR", "AWS Backup plan + selection", "Daily: Aurora, outputs, approved, models, training data (tag backup=true).", "Changed", STG_PRD),
    (R1, "12. Backup & DR", "Cross-region backup copy (optional)", "Copies backups to a second region if WBD approves.", "Same", PRD),
    # 13. Release 2
    (R2, "13. Release 2 - GenAI", "SSM parameters - genai_enabled flag + token quotas", "GenAI on/off without redeploy; per-BU token limits.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "Secrets Manager - LLM provider keys", "mmm/<env>/llm/openai, anthropic, google.", "New", ALL),
    (R2, "13. Release 2 - GenAI", "Amazon API Gateway - LLM gateway (private REST API)", "Single entry from the API to OpenAI / Anthropic / Google models.", "New", ALL),
    (R2, "13. Release 2 - GenAI", "API Gateway usage plans / throttling per BU", "Token/request quotas per business unit.", "New", ALL),
    (R2, "13. Release 2 - GenAI", "Lambda integrations per provider", "Add the provider key from Secrets Manager and call the provider.", "New", ALL),
    (R2, "13. Release 2 - GenAI", "VPC interface endpoint - execute-api", "Private access from the API to the LLM gateway.", "New", ALL),
    (R2, "13. Release 2 - GenAI", "API Gateway access + execution logs", "Encrypted logs of every LLM call.", "New", ALL),
    (R2, "13. Release 2 - GenAI", "Bedrock Guardrails", "Prompt injection, PII masking, grounding checks via ApplyGuardrail for every provider.", "Changed", ALL),
    (R2, "13. Release 2 - GenAI", "VPC interface endpoint - Bedrock runtime", "Private ApplyGuardrail (and Bedrock models if used) calls.", "Changed", ALL),
    (R2, "13. Release 2 - GenAI", "Bedrock model access (optional)", "Only if Anthropic is consumed through Bedrock [ASK].", "Changed", ALL),
    (R2, "13. Release 2 - GenAI", "S3 bucket - AI interaction logs", "Prompts, answers, sources, guardrail version (QA dashboard evidence).", "Changed", ALL),
    (R2, "13. Release 2 - GenAI", "API task role update", "execute-api:Invoke on the gateway + bedrock:ApplyGuardrail.", "Changed", ALL),
    (R2, "13. Release 2 - GenAI", "CloudWatch alarms - GenAI", "Gateway 4xx/5xx/latency, guardrail interventions, quota breaches.", "Changed", ALL),
    (R2, "13. Release 2 - GenAI", "CloudWatch dashboard - GenAI", "AI usage, latency, quotas and cost.", "Same", ALL),
    (R2, "13. Release 2 - GenAI", "AWS Budgets - LLM cost alert", "Alerts on LLM/gateway spend.", "Changed", ALL),
]

REMOVED = [
    ("Amazon ElastiCache (Valkey) + subnet group + snapshots", "Not in the v2 architecture; progress from Step Functions + Aurora (removed)", "5. Data & platform"),
    ("SQS FIFO queue + DLQ + queue policy", "Replaced by Step Functions async executions (removed; throttling Q2)", "5. Data & platform"),
    ("ECS service + task def - mmm-whatif-worker", "Simulation runs in the SageMaker optimization & decision job", "6. ECS compute"),
    ("ECS service + task def - mmm-optimizer-worker", "Optimizer runs as a SageMaker job via Step Functions", "6. ECS compute"),
    ("Application Auto Scaling on SQS backlog + task scale-in protection", "No queue workers on ECS", "6. ECS compute"),
    ("ECS service mmm-genai-gateway + SG + task role + Service Connect client", "LangGraph runs inside the API; LLMs via API Gateway", "10. Release 2 - GenAI"),
    ("CloudFront distribution, OAC, response headers policy, KeyValueStore + function", "Route 53 -> WAF -> public ALB; UI is an ECS container", "7. Edge & front door"),
    ("ACM certificate (us-east-1) + WAF web ACL (us-east-1, CloudFront scope)", "Only a regional certificate and regional WAF", "7. Edge & front door"),
    ("S3 bucket - frontend", "UI image in ECR instead of static files in S3", "5. Data & platform"),
    ("Amazon MWAA environment + execution role + SG + MWAA bucket", "EventBridge + Step Functions + Databricks Lakeflow Jobs", "5. Data & platform"),
    ("Lambda trigger (S3 -> EventBridge -> Lambda -> MWAA DAG)", "EventBridge targets the Step Functions state machine directly", "5. Data & platform"),
    ("S3 bucket - data-quality (Great Expectations)", "Data quality inside Lakeflow (Silver 'cleansed and validated') (removed)", "5. Data & platform"),
    ("RDS for PostgreSQL instance", "Aurora PostgreSQL Serverless v2 cluster (removed)", "5. Data & platform"),
    ("MLflow model registry (Databricks, production alias)", "SageMaker Model Registry + S3", "5. Data & platform"),
    ("Okta app per environment used directly by SPA/API", "Cognito user pool federated to Okta", "7. Edge & front door"),
    ("Secrets redis/token and edge/origin-verify", "No Redis and no CloudFront origin header", "4. Security & secrets"),
    ("KMS key - sqs", "No SQS (unless kept)", "1. Account foundation"),
    ("ECR repositories mmm/optimizer-worker, mmm/genai-gateway", "Replaced by mmm/ui, mmm/sagemaker-optimizer, mmm/sagemaker-training", "3. Container registry"),
    ("Bedrock endpoint policy allowing only the approved Bedrock model", "Multi-provider models through API Gateway; guardrails via ApplyGuardrail", "10. Release 2 - GenAI"),
]

# Implementation status on 5 Nov 2026 (repo wbd_devops_implmenetation_1); anything not listed = "Built".
WBD = "WBD account baseline - verified, not built by this repo"
STATUS = {
    "AWS account": WBD, "Service Control Policy (region lock)": WBD, "IAM Identity Center permission sets": WBD,
    "AWS CloudTrail": WBD, "Amazon GuardDuty": WBD, "AWS Security Hub": WBD, "AWS Config": WBD,
    "Amazon Inspector": WBD + " (ECR enhanced scanning is built)", "IAM Access Analyzer": WBD,
    "S3 Block Public Access (account level)": WBD, "EBS encryption by default": WBD, "Amazon Macie (optional)": WBD,
    "DynamoDB table - state lock (optional)": "Not built - S3 native lock file",
    "IAM roles - GitHub Actions": "Built: plan, apply, deploy, ecr-push, model-eval (reject only), model-approve",
    "AWS Budgets - SageMaker cost": "Not built - account budget + Cost Anomaly Detection cover it",
    "VPC interface endpoints": "Built (incl. states, sagemaker.api, execute-api and bedrock-runtime when GenAI is on); no SageMaker Runtime - no endpoints",
    "Security group - ALB": "Built - 0.0.0.0/0 by default, restrict with alb_ingress_cidrs (Q1)",
    "Transit Gateway attachment (optional)": "Built, off (enable_transit_gateway)",
    "Databricks PrivateLink endpoints": "Built, off (enable_databricks_privatelink) - workspace endpoint only",
    "Route 53 private hosted zone (Databricks PrivateLink)": "Built, off (with PrivateLink)",
    "Route 53 Resolver outbound endpoint + rules (optional)": "Built, off (enable_resolver_forwarding)",
    "Databricks customer-managed VPC subnets + SG (optional)": "Not built - WBD Databricks workspace / serverless compute",
    "EC2 key pair": "Not needed",
    "Secrets Manager secrets": "Built: DB users, Splunk HEC, LLM keys; Databricks OAuth secret is held by the EventBridge connection",
    "SSM Parameter Store parameters": "Built: feature flags + SageMaker image pointers (written by deploy.yml); IDs/ARNs are Terraform outputs -> GitHub vars",
    "Cognito identity provider (WBD Okta, OIDC/SAML)": "Built - SAML (okta_saml_metadata_url); groups -> custom:groups",
    "Cognito app client + hosted domain": "Built - confidential client for ALB authenticate-cognito (code flow)",
    "Cognito resource server + groups": "Not built - RBAC from Okta groups claim; ALB auth needs no custom scopes",
    "S3 bucket - training data": "Built (versioned; no Object Lock)",
    "S3 bucket - outputs": "Built as the 'results' bucket (runs/<run_id>/...)",
    "S3 bucket - SageMaker staging": "Not built - jobs read/write the results, training-data and models buckets",
    "S3 EventBridge notifications (landing bucket)": "Built (EventBridge on); refresh is scheduled or mmm.refresh event",
    "KMS keys per business unit (S3)": "Built, off (enable_data_platform) - key s3-<bu> for landing, lakehouse and training-data",
    "Aurora PostgreSQL cluster": "Built - Serverless v2 16.6; dev 1 x 0.5-4 ACU, stg 2 x 0.5-16, prd 2 x 1-32",
    "RDS Proxy": "Built - IAM auth + TLS",
    "Service Quotas increase (Fargate vCPU)": "Manual request before load test",
    "IAM roles - ECS task roles": "Built: api, ui, migrate, platform-check",
    "CloudWatch Logs data protection policy (optional)": "Built, off (enable_log_data_protection)",
    "ALB target groups (ip) - ui and api": "Built - /healthz (ui), /api/health (api)",
    "Application Auto Scaling policies": "Built - CPU target 60% for api and ui (dev 1-2 / stg 2-4 + 2-3 / prd 3-10 + 2-6)",
    "Route 53 DNS records": "Built if route53_zone_id is set; otherwise WBD DNS adds the CNAME",
    "SageMaker model package groups (per BU)": "Built with the data platform (<prefix>-<bu>)",
    "SageMaker job - optimization & decision (runtime)": "Built - Processing job (createProcessingJob.sync), ml.m5.xlarge default",
    "IAM role + log group + DLQ - results publisher": "Built without DLQ - Step Functions invokes it synchronously with retries",
    "SageMaker service quotas + warm pools": "Manual quota request; no warm pools (Processing jobs)",
    "SageMaker endpoint - simulation (optional)": "Not built - what-if runs in the API",
    "EventBridge Scheduler - scheduled refresh": "Built, off (enable_data_platform + enable_model_refresh_schedule); one per BU",
    "EventBridge rule - manual / app-triggered refresh": "Built, off (enable_data_platform); scripts/trigger-model-refresh.sh",
    "EventBridge connection (Databricks OAuth)": "Built, off (enable_data_platform)",
    "Step Functions state machine - model refresh": "Built, off - Databricks job -> train -> evaluate -> register",
    "IAM role + log group - model refresh state machine": "Built, off",
    "Databricks Lakeflow Jobs": "Data engineers; deployed by databricks.yml (Asset Bundle, GitHub OIDC)",
    "Unity Catalog storage credential + external locations": "WBD Databricks admins; the IAM role is built",
    "IAM roles - SageMaker training + evaluation": "Built, off",
    "SageMaker training job (runtime)": "Built, off - ml.m5.2xlarge default",
    "SageMaker processing job - evaluation (runtime)": "Built, off",
    "SageMaker Model Registry - model versions": "Built - PendingManualApproval -> Approved by model-governance.yml",
    "EventBridge rule - model package state change": "Built -> SNS alerts",
    "SageMaker Studio domain (optional)": "Not built",
    "AWS Chatbot / Q Developer in chat apps (optional)": "Not built - SNS email",
    "CloudWatch Application Signals": "Built, off (enable_application_signals)",
    "CloudWatch alarms": "Built: ALB/API, ECS, Aurora, Step Functions, Lambda; model thresholds checked by model-governance.yml",
    "EventBridge rules -> SNS": "Built: GuardDuty High, ECS deployment failure, model package state; failures of runs via Step Functions alarms",
    "CloudWatch dashboards": "Built - one platform dashboard",
    "IAM role + S3 backup bucket - Firehose": "Built, off (enable_splunk_shipping)",
    "Kinesis Data Firehose (to Splunk)": "Built, off (enable_splunk_shipping)",
    "IAM role - CloudWatch Logs subscription": "Built, off (enable_splunk_shipping)",
    "CloudWatch Logs subscription filters": "Built, off (enable_splunk_shipping)",
    "S3 bucket + IAM role - Synthetics (optional)": "Not built (gap)",
    "CloudWatch Synthetics canary (optional)": "Not built (gap) - deploy smoke test instead",
    "AWS Backup vault": "Built (vault lock in prod)",
    "AWS Backup plan + selection": "Built - Aurora, results, approved-worm, models (tag backup=true)",
    "Cross-region backup copy (optional)": "Built, off (enable_cross_region_copy)",
    "SSM parameters - genai_enabled flag + token quotas": "Built - genai_enabled flag; token quotas enforced by the API",
    "Secrets Manager - LLM provider keys": "Built, off (enable_genai) - one per entry in llm_providers",
    "Amazon API Gateway - LLM gateway (private REST API)": "Built, off (enable_genai)",
    "API Gateway usage plans / throttling per BU": "Built as stage throttling; per-BU quotas enforced by the API",
    "Lambda integrations per provider": "Built as one proxy Lambda for all providers",
    "VPC interface endpoint - execute-api": "Built, off (enable_genai)",
    "API Gateway access + execution logs": "Built, off (enable_genai)",
    "Bedrock Guardrails": "Built, off (enable_genai)",
    "VPC interface endpoint - Bedrock runtime": "Built, off (enable_genai)",
    "Bedrock model access (optional)": "Not built",
    "S3 bucket - AI interaction logs": "Not built - API logs to CloudWatch (and Splunk)",
    "API task role update": "Built, off (enable_genai)",
    "CloudWatch alarms - GenAI": "Built, off - gateway 5xx/latency",
    "CloudWatch dashboard - GenAI": "Not built - platform dashboard",
    "AWS Budgets - LLM cost alert": "Not built - account budget",
}

# (question, default implemented, still to confirm with WBD)
DECISIONS = [
    ("Aurora or RDS PostgreSQL? Serverless? RDS Proxy?", "Aurora PostgreSQL Serverless v2 16.6 + RDS Proxy (IAM auth, TLS)", "No"),
    ("Cognito federated to Okta - OIDC or SAML? Owner?", "SAML; Terraform owns the user pool, WBD IAM owns the Okta app (one per env)", "Q5 - group names"),
    ("CloudFront removed? ALB public or WBD ranges? Shield Advanced?", "Removed; public ALB + regional WAF (managed rules + rate limit) + Cognito; alb_ingress_cidrs to restrict; no Shield Advanced", "Q1"),
    ("ElastiCache and SQS dropped? Progress and throttling?", "Dropped; progress = Step Functions DescribeExecution + run row in Aurora; throttling = Step Functions retries on SageMaker limits + app-side concurrency limit", "Q2"),
    ("What-if in ~10 s with SageMaker?", "What-if runs in the API; SageMaker only for full optimization runs (no endpoint)", "No"),
    ("SageMaker instance types, quotas, warm pools, Studio?", "ml.m5.xlarge (optimizer/evaluation), ml.m5.2xlarge (training); quota request before load test; no warm pools; no Studio", "Sizes after load test"),
    ("Databricks workspace and compute location?", "WBD workspace; Step Functions HTTP Task via EventBridge connection (OAuth); PrivateLink optional; no customer-managed VPC", "Q4 - IP access list"),
    ("Databricks code deployment?", "Asset Bundle in data/databricks/ deployed by databricks.yml with GitHub OIDC; no data-v* tags", "Q6 - service principals"),
    ("LLM gateway - ours or WBD central? Providers?", "Ours: private API Gateway + one proxy Lambda; providers in llm_providers", "Provider list"),
    ("Approval to send data to external LLM providers?", "GenAI built but off (enable_genai=false); guardrail PII masking/blocking on every call", "Q3"),
    ("GenAI still Release 2?", "Yes - behind enable_genai and the genai_enabled SSM flag", "No"),
    ("Splunk still the log store?", "CloudWatch primary; Firehose to Splunk built but off", "HEC endpoint"),
    ("MLflow replaced by SageMaker Model Registry?", "Yes; model-governance.yml: eval role rejects, approve role (env <env>-model-promotion) approves and publishes curves; rollback re-approves previous version", "No"),
    ("Results publisher DLQ?", "No DLQ - invoked synchronously by Step Functions with retries; failures alarm", "No"),
    ("Autoscaling signals?", "CPU target tracking (60%) for api and ui", "No"),
]

YELLOW = PatternFill("solid", fgColor="FFF2CC")
GREEN = PatternFill("solid", fgColor="E2EFDA")
GREY = PatternFill("solid", fgColor="E7E6E6")
HEAD = PatternFill("solid", fgColor="1F3864")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def build_xlsx():
    wb = Workbook()
    wb.remove(wb.active)
    for env in ALL:
        ws = wb.create_sheet(env)
        ws["A1"] = f"WBD MMM - {env.capitalize()} - AWS resources in creation order (v2: Hybrid Lakehouse + MLOps, from wbd_Presentation.pptx)"
        ws["A1"].font = Font(bold=True, size=13)
        ws["A2"] = ("Step numbers match across Dev, Staging and Prod. Yellow = new in v2, green = changed vs v1 "
                    "(aws_resource_list.xlsx), grey = not built. Removed v1 resources are on the 'removed_vs_v1' sheet. "
                    "[ASK] items are resolved on the 'decisions' sheet (implemented 5 Nov 2026).")
        ws["A2"].font = Font(italic=True, size=9)
        headers = ["Step", "Release", "Layer", "AWS Resource", "Description", "Change vs v1", "Implemented (5 Nov 2026)"]
        ws.append([])
        ws.append(headers)
        for c in ws[4]:
            c.font = Font(bold=True, color="FFFFFF")
            c.fill = HEAD
            c.border = BORDER
            c.alignment = Alignment(vertical="center", wrap_text=True)
        for step, (rel, layer, res, desc, change, envs) in enumerate(ROWS, 1):
            if env not in envs:
                continue
            status = STATUS.get(res, "Built")
            ws.append([step, rel, layer, res, desc, change, status])
            fill = GREY if status.startswith(("Not ", "WBD", "Manual", "Data engineers")) else \
                YELLOW if change == "New" else GREEN if change == "Changed" else None
            for c in ws[ws.max_row]:
                c.border = BORDER
                c.alignment = Alignment(vertical="top", wrap_text=True)
                if fill:
                    c.fill = fill
        for col, w in zip("ABCDEFG", (6, 10, 24, 46, 80, 12, 60)):
            ws.column_dimensions[col].width = w
        ws.freeze_panes = "A5"

    ws = wb.create_sheet("removed_vs_v1")
    ws["A1"] = "v1 resources that are not in the v2 architecture"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["#", "v1 layer", "Removed resource", "Replaced by / reason"])
    for c in ws[3]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD
        c.border = BORDER
    for i, (res, why, layer) in enumerate(REMOVED, 1):
        ws.append([i, layer, res, why])
        for c in ws[ws.max_row]:
            c.border = BORDER
            c.alignment = Alignment(vertical="top", wrap_text=True)
    for col, w in zip("ABCD", (5, 24, 60, 70)):
        ws.column_dimensions[col].width = w

    ws = wb.create_sheet("decisions")
    ws["A1"] = "Open points resolved with the simpler industry-standard default (implemented 5 Nov 2026)"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["#", "Question", "Default implemented", "Still to confirm with WBD"])
    for c in ws[3]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD
        c.border = BORDER
    for i, row in enumerate(DECISIONS, 1):
        ws.append([i, *row])
        for c in ws[ws.max_row]:
            c.border = BORDER
            c.alignment = Alignment(vertical="top", wrap_text=True)
    for col, w in zip("ABCD", (5, 50, 80, 24)):
        ws.column_dimensions[col].width = w
    wb.save(OUT / "aws_resource_list_2.xlsx")


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
    p("DevOps Implementation Plan v2 - Hybrid Lakehouse + MLOps on AWS (ECS Fargate + SageMaker + Databricks)", None).runs[0].bold = True
    note = p("Version 2 of wbd_mmm_ecs_final.docx, updated for the client architecture in wbd_Presentation.pptx "
             "(slide 1: auto ML training; slide 2: optimization and explainable planning). Items marked [ASK] / [ASM] "
             "were implemented on 5 Nov 2026 with the defaults in section 10; section 10a lists what was built.")
    note.runs[0].italic = True
    note.runs[0].font.color.rgb = RGBColor(0x59, 0x59, 0x59)

    h("1. What changed vs v1")
    table(["Area", "v1 (wbd_mmm_ecs_final.docx)", "v2 (client architecture)", "DevOps impact"], [
        ("Front door", "CloudFront + WAF + ALB (CloudFront-only ingress)", "Route 53 + regional WAF + public ALB", "Remove edge module; add regional WAF; ALB SG opens 443"),
        ("Frontend", "React static files in S3 via CloudFront", "ECS UI Fargate web container", "New ui service, ECR repo, ui-ci image build"),
        ("Login", "Okta app per env", "Cognito (enterprise IdP federation)", "New cognito module; ALB authenticate-cognito"),
        ("API", "ECS mmm-api (FastAPI)", "ECS API with LangGraph + QA dashboard", "Task role adds Step Functions + LLM gateway"),
        ("Database", "RDS PostgreSQL + RDS Proxy", "Aurora PostgreSQL (plans, runs, allocations)", "New aurora module replaces rds [ASK]"),
        ("Optimization / what-if", "ECS whatif + optimizer workers, SQS FIFO", "Step Functions -> SageMaker job -> S3 outputs -> Lambda publisher", "Remove workers/SQS; add step-functions, sagemaker, lambda"),
        ("Cache", "ElastiCache Valkey", "Not shown", "Remove [ASK]"),
        ("Data orchestration", "MWAA + EventBridge + Lambda", "EventBridge -> Step Functions -> Databricks Lakeflow Jobs", "Remove mwaa + data-trigger; add scheduler + state machine"),
        ("Data layers", "Databricks Bronze/Silver/Gold (dbt)", "Databricks + Delta Lake on S3; Gold per-BU tables; Feature Export", "Lakehouse bucket + UC external locations"),
        ("Training", "Databricks + MLflow", "SageMaker training + evaluation + registration", "SageMaker roles, training images, quotas"),
        ("Registry", "MLflow production alias", "SageMaker Model Registry + S3 (response curves)", "model-governance approves model packages"),
        ("GenAI", "Bedrock only, private genai ECS gateway", "LangGraph in API -> API Gateway -> OpenAI/Anthropic/Google + Bedrock Guardrails", "llm-gateway module; egress approval [ASK]"),
    ])

    h("2. Target platform")
    p("The WBD MMM application (UI + API) runs on Amazon ECS with AWS Fargate in three WBD-owned AWS accounts "
      "(Dev, Stage, Prod). Optimization, simulation and model training run on Amazon SageMaker jobs inside the VPC, "
      "orchestrated by AWS Step Functions. Data engineering runs on Databricks on AWS with Delta Lake on S3. "
      "Users enter through Route 53, AWS WAF and a public Application Load Balancer and sign in through Amazon Cognito "
      "federated to the WBD enterprise identity provider.", "Decision: ")
    p("Terraform - GitHub Actions (OIDC) - Amazon ECR - Amazon ECS on Fargate + ALB - Route 53 - AWS WAF - ACM - "
      "Amazon Cognito - Aurora PostgreSQL (+ RDS Proxy) - S3 (landing, Delta Lake, training data, models, outputs, "
      "exports, Object Lock) - KMS - Secrets Manager + Parameter Store - AWS Step Functions - Amazon EventBridge "
      "(+ Scheduler) - AWS Lambda - Amazon SageMaker (training, processing, Model Registry) - Databricks (Lakeflow "
      "Jobs, Unity Catalog) - Amazon API Gateway - Amazon Bedrock Guardrails - CloudWatch + CloudTrail - AWS Backup.",
      "Platform stack: ")
    p("React + TypeScript - Python / FastAPI - scikit-learn / XGBoost / LangGraph - SciPy - RDS PostgreSQL + "
      "Databricks / S3 - ECS - AWS recommended.", "Prescribed stack (WBD): ")

    h("3. Application components and runtimes")
    table(["Component", "Runs on", "What it does", "How it scales"], [
        ("mmm-ui", "ECS Fargate", "React + TypeScript web container", "CPU target tracking; Dev 1, Stage 2, Prod 2-3 tasks"),
        ("mmm-api", "ECS Fargate", "FastAPI + LangGraph + QA dashboard; starts runs, reads results", "CPU / ALB requests; Dev 1, Stage 2, Prod 3+ across AZs"),
        ("mmm-migrate", "ECS Fargate (one-off)", "Alembic DB migration before each deploy", "Once per deploy"),
        ("Optimization & decision job", "SageMaker processing/training job", "Model Summarizer, Optimizer, Simulation", "One job per run; quotas sized for 50-150 planners"),
        ("Results publisher", "AWS Lambda (VPC)", "Writes plans, runs, allocations from S3 outputs to Aurora", "Per run; reserved concurrency"),
        ("Optimization workflow", "Step Functions (Standard)", "Async run: job -> publish, retries, timeouts", "One execution per run id"),
        ("Model refresh workflow", "Step Functions + EventBridge", "Lakeflow job -> Parquet -> train -> evaluate -> register", "Scheduled / manual / app-triggered"),
        ("Lakeflow Jobs", "Databricks on AWS", "Ingestion, Bronze, Silver, Gold, Feature Export", "Databricks job clusters"),
        ("Model training + evaluation", "SageMaker training / processing jobs", "Multi-stage models; baseline, channel lift, title adjustment", "Per refresh"),
        ("LLM gateway (Release 2)", "Amazon API Gateway (+ Lambda)", "OpenAI / Anthropic / Google models; Bedrock Guardrails", "Usage plans per BU"),
    ])

    h("4. The two flows")
    h("4.1 Auto ML training (slide 1)", 2)
    bullets([
        "Scheduled refresh (EventBridge Scheduler), manual or application-triggered refresh -> EventBridge -> Step Functions (schedule / manual, wait / retry).",
        "Step Functions runs Databricks Lakeflow Jobs (tasks, dependencies, retries): ingestion from S3 into the Databricks catalog -> Bronze (ingested raw data) -> Silver (cleansed, validated) -> Gold (per-BU modeling tables, adstock & saturation).",
        "Raw data landing in the catalog comes from S3 (3+ years of historical inventory). Delta Lake storage for Bronze/Silver/Gold is backed by S3.",
        "Feature Export (plans, runs, allocations) -> Step Functions publishes Parquet files with metadata to S3 (training data: immutable Parquet + metadata).",
        "AWS-native SageMaker modeling (in the VPC through SageMaker ENIs): model training (trained and tuned multi-stage models) -> evaluation (baseline -> channel lift -> title adjustment) -> model registration (approved model versioned and registered).",
        "SageMaker Registry + S3 store the approved models and response curves used by the optimization job.",
    ])
    h("4.2 Optimization and explainable planning (slide 2)", 2)
    bullets([
        "Planner uploads inventory, chooses an objective, runs and compares -> DNS / WAF -> ALB (HTTPS, public entry) -> ECS UI -> ECS API.",
        "SSO / authentication through Cognito (enterprise identity provider). UI + API images built and deployed from ECR (versioned releases).",
        "ECS API (FastAPI with LangGraph and QA dashboard) reads/writes Aurora PostgreSQL (plans, runs, allocations).",
        "API -> Step Functions (async execution) -> SageMaker job for optimization & decision: Model Summarizer (channel contribution, response curves, baseline, performance metrics), Optimizer (constrained or unconstrained across BUs, titles and periods using mixed units, owned inventory at the center), Simulation (what-if scenarios, scenario comparison, logged override).",
        "The job reads the approved model (SageMaker Registry) and approved MMM response curves (S3) and writes the full run evidence to S3 outputs; a Lambda results publisher writes the results to Aurora.",
        "API -> Amazon API Gateway -> OpenAI / Anthropic / Google models, with Amazon Bedrock Guardrails.",
        "Sized for 50-150 planners working at the same time in planning seasons.",
    ])

    h("5. Deployment approach - Flywheel pattern on AWS (updated)")
    table(["Flywheel (Azure)", "WBD MMM v2 (AWS)"], [
        ("Container Apps Environment", "ECS cluster (Fargate)"),
        ("Container App + revision", "ECS service (ui, api) + task definition revision"),
        ("Container App Job", "SageMaker job via Step Functions (optimization); ECS one-off task (migration)"),
        ("Built-in ingress + managed certificate", "Public ALB + ACM + regional WAF; Route 53"),
        ("Entra ID login", "Cognito federated to WBD Okta"),
        ("Azure Container Registry", "Amazon ECR (per env, digest promotion)"),
        ("Key Vault", "Secrets Manager / Parameter Store"),
        ("Log Analytics", "CloudWatch Logs + Container Insights + Application Signals"),
        ("PostgreSQL Flexible Server", "Aurora PostgreSQL (+ RDS Proxy)"),
        ("Storage account / Blob", "Amazon S3"),
        ("Azure ML / model registry", "SageMaker training + Model Registry"),
        ("Recovery / Backup vault", "AWS Backup"),
        ("azure/login (OIDC)", "aws-actions/configure-aws-credentials (OIDC)"),
        ("Pre-deploy pg_dump", "Aurora cluster snapshot before Prod migrations"),
    ])

    h("6. Alternatives to confirm")
    table(["#", "Alternative", "Why"], [
        ("A", "SageMaker Pipelines for train -> evaluate -> register", "Native ML lineage; Step Functions stays the top-level orchestrator"),
        ("B", "Simulation on a SageMaker real-time / serverless endpoint", "Meets the ~10 s what-if target; jobs take minutes to start"),
        ("C", "Keep CloudFront in front of the ALB", "Edge caching, DDoS absorption at the edge; not in the slides"),
        ("D", "Keep SQS as a buffer before Step Functions", "Throttles 50-150 planners against SageMaker quotas"),
        ("E", "Anthropic through Amazon Bedrock instead of the public API", "Keeps that traffic inside AWS (PrivateLink)"),
        ("F", "Aurora Serverless v2", "Scales with planning seasons; lower cost out of season"),
        ("G", "Lakeflow expectations for data quality", "Replaces the separate Great Expectations bucket"),
    ])

    h("7. Environments")
    table(["Environment", "AWS account", "Use", "Size", "Approves changes"], [
        ("Dev", "wbd-mmm-dev", "Daily development, automated tests", "Small; scale down at night", "Automatic"),
        ("Stage", "wbd-mmm-stage", "Release testing, UAT, parallel run, performance and security tests", "Close to Prod", "EY lead"),
        ("Prod", "wbd-mmm-prod", "Live use by WBD planners (50-150 concurrent)", "Full, HA (3 AZs)", "WBD approver + CAB"),
        ("Shared (optional)", "wbd-mmm-shared", "Only if WBD requires central ECR/runners [ASK]", "Small", "DevOps lead"),
    ])
    h("7.1 Environment differences", 2)
    table(["Setting", "Dev", "Stage", "Prod"], [
        ("Availability Zones", "2", "3", "3"),
        ("NAT gateways", "1", "1 per AZ", "1 per AZ"),
        ("ECS UI / API tasks", "1 / 1", "2 / 2", "2-3 / 3+ across AZs"),
        ("Aurora", "1 small writer", "Writer + reader", "Writer + reader(s), deletion protection"),
        ("SageMaker instance types / quotas", "Small, low quota", "Prod-like for performance tests", "Sized from load test (50-150 planners)"),
        ("Databricks job clusters", "Smallest", "Small/medium", "Sized from data volume"),
        ("Backups", "Automated (PITR 7 d)", "AWS Backup (14 d) + restore tests", "AWS Backup (35 d), vault lock, cross-region if approved"),
        ("Log retention", "30 days", "90 days", "90+ days (+ Splunk)"),
        ("Data allowed", "Synthetic / masked", "Approved prod-like clone", "Production"),
        ("Deployment approval", "Automatic", "EY lead", "WBD approver + CAB"),
        ("Cost controls", "Scale UI/API down at night, small jobs", "Scale down outside test windows", "Budgets, Savings Plans"),
    ])

    h("8. Stages at a glance")
    table(["Stage", "Name", "Main output"], [
        ("0", "Access", "Logins to GitHub, AWS, Databricks, SageMaker, Splunk"),
        ("1", "Questions for the client", "Answers incl. v2 questions (section 10)"),
        ("2", "Design and approval", "Approved v2 design pack"),
        ("3", "Account foundation", "Accounts, SSO, KMS, state, OIDC, budgets"),
        ("4", "Networking", "VPC, subnets, NAT, endpoints (incl. states, sagemaker), SGs"),
        ("5", "Security baseline + identity", "IAM, encryption, secrets, Cognito"),
        ("6", "Data & storage", "ECR, S3 buckets, Aurora (+ Proxy)"),
        ("7", "ECS on Fargate", "Cluster, UI + API services, ALB"),
        ("8", "Docker", "UI, API, SageMaker optimizer/training images"),
        ("9", "Optimization engine", "Step Functions + SageMaker jobs + Lambda publisher"),
        ("10", "Data & ML platform", "Lakeflow, Delta Lake, training, registry, governance"),
        ("11", "CI/CD", "Pipelines for UI, API, images, infra, Databricks, models"),
        ("12", "Front door and login", "Route 53, WAF, ACM, Cognito"),
        ("13", "Logging and monitoring", "Dashboards, alerts, log shipping"),
        ("14", "Backup and DR", "Backups, restore tests, DR plan"),
        ("15", "Testing and Release 1 go-live", "Performance, pen test, parallel run, UAT, cutover"),
        ("16", "Release 2 - GenAI", "LLM gateway, guardrails, QA dashboard"),
        ("17", "Handover and operations", "Runbooks, KT, WBD runs it alone"),
    ])

    h("9. Stages")
    stages = [
        ("Stage 0 - Access", ["Access to GitHub, AWS (SSO + CLI), Databricks workspace, SageMaker, Splunk, CloudWatch, Jira.",
                              "Contacts: WBD Cloud Platform, Network, Identity (Okta/Cognito), Databricks admins, Data Science lead, InfoSec, CAB."]),
        ("Stage 1 - Questions for the client", ["All v1 questions (accounts, region, CIDRs, guardrails, DNS, CI/CD, scanners, Splunk, retention, RPO/RTO, CAB, feeds, history, LLMs, approvers) plus the v2 questions in section 10."]),
        ("Stage 2 - Design and approval", ["Deployment diagram from wbd_Presentation.pptx with network detail.",
                                           "ADRs: ECS for UI/API, SageMaker for optimization and training, Step Functions orchestration, Cognito federation, Aurora, regional WAF without CloudFront, LLM gateway, SageMaker Registry.",
                                           "Threat model incl. external LLM data egress; RPO/RTO; naming and tagging (unchanged: mmm-<env>-<component>)."]),
        ("Stage 3 - Account foundation", ["State bucket + lock per account; KMS keys per purpose (rds/Aurora, s3, logs, secrets, ecr, sagemaker) + per-BU keys.",
                                          "Permission boundary on every role; GitHub OIDC + gha-plan/apply/deploy/ecr-push/ecr-read; budgets incl. SageMaker."]),
        ("Stage 4 - Networking", ["VPC /19; public, private-app (ECS, Lambda, SageMaker ENIs), private-data (Aurora), private-endpoint.",
                                  "Endpoints: S3, DynamoDB (gateway); ECR api/dkr, STS, Secrets Manager, SSM, SSM Messages, KMS, Logs, Monitoring, X-Ray, Step Functions, SageMaker API (+ Runtime), execute-api and Bedrock runtime in Release 2.",
                                  "Security groups: ALB (443 public/WBD ranges), UI and API (from ALB), SageMaker jobs and Lambda (no inbound), RDS Proxy (API, Lambda, migrate), Aurora (Proxy only), endpoints (VPC 443).",
                                  "Databricks PrivateLink (workspace + SCC relay) and private DNS; optional Transit Gateway and Resolver."]),
        ("Stage 5 - Security baseline and identity", ["Engineers via Identity Center; pipelines via OIDC; workloads via per-service/per-job roles.",
                                                       "App users: Cognito user pool federated to WBD Okta (MFA, step-up for approvals/overrides) -> RBAC in the API -> PostgreSQL row-level security per BU.",
                                                       "Encryption: KMS on S3, Aurora, logs, secrets, ECR, SageMaker volumes/outputs/artifacts; TLS 1.2+ on ALB, Aurora, API Gateway.",
                                                       "Secrets in Secrets Manager (DB users, Databricks OAuth SP, third parties, LLM keys in R2); settings in SSM."]),
        ("Stage 6 - Data & storage", ["ECR: mmm/api, mmm/ui, mmm/sagemaker-optimizer, mmm/sagemaker-training (immutable, scanned, lifecycle).",
                                      "S3: landing, lakehouse (Delta), training-data (immutable), models (artifacts + response curves), outputs (run evidence), approved-worm, exports (30 d), logs; versioning, KMS, TLS-only, access logs.",
                                      "Aurora PostgreSQL: IAM auth, force_ssl, pgaudit, PI, Multi-AZ in stg/prd, deletion protection in prod; RDS Proxy for ECS + Lambda."]),
        ("Stage 7 - ECS on Fargate", ["Cluster with Container Insights enhanced; task execution role; one task role per service; log groups with retention + KMS; ECS Exec via break-glass only.",
                                      "Services mmm-ui and mmm-api behind the public ALB (path routing /api/* and /*), migrate one-off task; rolling 100/200, circuit breaker rollback, ignore_changes on task_definition and desired_count."]),
        ("Stage 8 - Docker", ["Multi-stage, pinned base images, non-root, read-only file system, lock files, no secrets, .dockerignore.",
                              "Images: mmm/ui (React build on nginx), mmm/api (FastAPI + LangGraph), mmm/sagemaker-optimizer and mmm/sagemaker-training (SageMaker container contract: /opt/ml paths).",
                              "Tags: sha-<7> on main, vX.Y.Z-rcN and vX.Y.Z on the same digest; Trivy + Inspector + SBOM."]),
        ("Stage 9 - Optimization engine", ["Step Functions 'optimization' state machine started by the API (execution name = run id -> idempotent).",
                                           "SageMaker job (optimizer image) in the VPC reads the latest Approved model package per BU + response curves, writes full run evidence to S3 outputs.",
                                           "Lambda results publisher writes plans/runs/allocations to Aurora via RDS Proxy; failures -> run marked failed + alarm.",
                                           "Quotas and warm pools for 50-150 planners. What-if ~10 s target needs a decision (endpoint vs job vs in-API) [ASK]."]),
        ("Stage 10 - Data & ML platform", ["EventBridge Scheduler + manual/app refresh event -> Step Functions 'model-refresh'.",
                                           "Databricks Lakeflow Jobs via Step Functions HTTP Task (Databricks OAuth): ingestion -> Bronze -> Silver -> Gold -> Feature Export; Delta Lake on S3; Unity Catalog lineage.",
                                           "Parquet + metadata published immutable to training-data; SageMaker training -> evaluation (baseline, channel lift, title adjustment) -> model package PendingManualApproval.",
                                           "Named WBD approver approves the model package (GitHub model-promotion environment); optimizer picks up the new Approved version, no redeploy."]),
        ("Stage 11 - CI/CD with GitHub Actions", ["api-ci, ui-ci (container), sagemaker-image-ci, terraform (PR plan, apply dev -> stg -> prd, nightly drift), deploy (promote digests, Aurora snapshot in prod, migration, ECS ui+api, optimizer image tag, smoke, rollback, release record), databricks (Asset Bundles), model-governance (approve model package), repo-checks.",
                                                  "GitHub Environments dev/staging/prod (+ <env>-model-promotion); actions pinned to commit SHAs; CODEOWNERS."]),
        ("Stage 12 - Front door and login", ["Route 53 records by WBD -> ALB; ACM regional certificate; regional WAF (managed rules, rate limit, logs).",
                                             "Cognito: user pool, Okta federation, UI app client (PKCE), API resource server/scopes, BU/role groups; ALB authenticate-cognito [ASM].",
                                             "Done when: login + MFA works, unauthenticated users are redirected, one BU cannot see another BU's data."]),
        ("Stage 13 - Logging and monitoring", ["CloudWatch metrics, logs, Container Insights, Application Signals, dashboards, alarms -> SNS; CloudTrail; logs to Splunk if kept [ASK].",
                                               "Key alerts: availability < 99.5 %, API 5xx > 2 %, optimization runtime (> 2 min standard, > 10 min large), what-if > 10 s, Step Functions/SageMaker/Lambda failures, Aurora CPU/connections/storage, stale data, failed model thresholds/drift, GuardDuty High, break-glass, cert expiry, budget."]),
        ("Stage 14 - Backup and DR", ["Aurora PITR + AWS Backup (vault lock in prod, cross-region if approved); S3 versioning + Backup for outputs, approved, models, training-data.",
                                      "Restore tests in Stage; rebuild an environment from code; business-continuity one-pager."]),
        ("Stage 15 - Testing and Release 1 go-live", ["Performance test with 50 / 100 / 150 planners (optimization + what-if); SageMaker quota check; DAST and pen test; Aurora failover and AZ-loss tests; parallel run and UAT; Well-Architected review; CAB; cutover + hypercare."]),
        ("Stage 16 - Release 2 GenAI", ["LangGraph in the API; Amazon API Gateway (private) as the LLM gateway to OpenAI / Anthropic / Google with per-BU usage plans; provider keys in Secrets Manager.",
                                        "Bedrock Guardrails applied (ApplyGuardrail) to every prompt and answer for every provider; QA dashboard logs answers with sources, model, prompt/template and guardrail versions.",
                                        "Written WBD approval for sending data to external providers [ASK]; evaluation test set before each promotion."]),
        ("Stage 17 - Handover", ["Runbooks (deploy, rollback, scale for planning season, failed optimization run, failed model refresh, Lambda DLQ, Aurora restore/failover, Cognito/IdP outage, secret/cert rotation, model rollback, GenAI on/off, security incident, break-glass); KT, shadowing, reverse shadowing, sign-off."]),
    ]
    for name, items in stages:
        h(name, 2)
        bullets(items)

    h("10. Questions for WBD (v2) and the default implemented")
    p("All open points were implemented on 5 Nov 2026 with the simpler industry-standard default below; "
      "the last column lists what WBD still has to confirm (Q1-Q6 in PROJECT_CONTEXT.md section 5.2).")
    table(["#", "Question", "Default implemented", "Still to confirm"],
          [(str(i), *row) for i, row in enumerate(DECISIONS, 1)])

    h("10a. Implementation status (5 Nov 2026)")
    bullets([
        "Built in Terraform for dev, staging and prod (staging/prod synced from dev): network, KMS, ECR (mmm/api, mmm/ui, "
        "mmm/sagemaker-optimizer, mmm/sagemaker-training), S3 buckets, Aurora Serverless v2 + RDS Proxy, Cognito (Okta SAML), "
        "ALB + regional WAF, ECS api/ui/migrate/platform-check, optimization state machine + SageMaker role + publisher Lambda, "
        "monitoring, log shipping (off), backup.",
        "Built but off by default: data platform (enable_data_platform: Databricks connection, model-refresh state machine, "
        "schedules, model package groups), GenAI (enable_genai: LLM gateway, guardrails), Splunk shipping, Transit Gateway, "
        "Resolver, Databricks PrivateLink, Application Signals, cross-region backup copy.",
        "Removed: rds, elasticache, sqs, edge (CloudFront), mwaa, data-trigger and bedrock modules; whatif/optimizer workers; "
        "genai-gateway service; MWAA DAG folder and data.yml.",
        "Pipelines: api-ci, ui-ci, optimizer-ci, training-ci, publisher-ci, deploy (promotion, migration, smoke, SSM image "
        "pointers, Lambda alias, rollback), terraform, databricks (Asset Bundle), model-governance, repo-checks.",
        "Not built (decision): SageMaker endpoint, Studio, SageMaker staging bucket, Cognito resource server, "
        "API Gateway usage plans per BU, AI interaction-log bucket, GenAI dashboard, LLM / SageMaker budgets, publisher DLQ, "
        "Synthetics canary, Chatbot.",
    ])

    h("11. Risks")
    table(["Risk", "Mitigation"], [
        ("SageMaker job start-up (minutes) vs ~10 s what-if target", "Endpoint or in-API simulation for what-if; warm pools; measure in Stage"),
        ("External LLM providers move data outside AWS", "Written approval, guardrails on every call, data minimisation, Bedrock-hosted models where possible"),
        ("Public ALB without CloudFront", "Regional WAF, rate limits, Shield; restrict to WBD ranges if possible"),
        ("SageMaker quotas/cost with 150 concurrent planners", "Quota increases before load test, concurrency guard, SageMaker budget"),
        ("Two orchestrators (Step Functions + Lakeflow)", "Step Functions owns end-to-end state; Lakeflow owns Databricks tasks only"),
        ("Re-work of the v1 code already built", "Keep shared modules; replace module by module behind flags (see PROJECT_CONTEXT_2.md)"),
    ])

    h("12. AWS resource list summary (details in aws_resource_list_2.xlsx)")
    table(["Layer", "Resources", "Dev", "Stage", "Prod"], [
        (layer,
         sum(1 for r in ROWS if r[1] == layer),
         sum(1 for r in ROWS if r[1] == layer and "dev" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and "staging" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and "prod" in r[5]))
        for layer in dict.fromkeys(r[1] for r in ROWS)
    ])
    d.save(OUT / "wbd_mmm_ecs_final_2.docx")


build_xlsx()
build_docx()
print("rows:", len(ROWS), "removed:", len(REMOVED))

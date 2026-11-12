"""Builds aws_resource_list_4.xlsx and wbd_mmm_ecs_final_4.docx (v4 architecture, WBD_MMM_Architecture_4.pptx).

The workbook has the full v4 resource list per environment (kept + changed + new, like aws_resource_list_3.xlsx),
a summary, the v4-only detail (v4_new_resources, v4_changes) and what v4 removed (removed_vs_v3).

Usage: uv run --no-project --with openpyxl --with python-docx python build_v4.py <docs/requirements> [--xlsx-only]
"""
import re
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

WBD = "WBD account baseline - verified, not built by this repo"
KEEP = "Built - keep"

# (release, layer, resource, description, change vs v3, environments, repo today (v3 build) -> v4 action)
ROWS = [
    # 1. Account foundation
    (R1, "1. Account foundation", "AWS account", "Separate WBD-owned AWS account for the environment.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "Service Control Policy (region lock)", "Blocks AWS regions that WBD has not approved.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "IAM Identity Center permission sets", "SSO roles for engineers (ReadOnly/Developer/DevOps/Security/BreakGlass); no IAM users.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "AWS CloudTrail", "Records every API call for audit (Logging/Operations band on the slides).", "Same", ALL, WBD),
    (R1, "1. Account foundation", "Amazon GuardDuty", "Detects threats and suspicious activity.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "AWS Security Hub", "Shows all security findings in one place.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "AWS Config", "Tracks resource settings and flags non-compliant ones.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "Amazon Inspector", "Scans ECR images (api, ui, NEW optimizer ECS image, SageMaker training image).", "Changed", ALL, WBD + " (ECR enhanced scanning is built)"),
    (R1, "1. Account foundation", "IAM Access Analyzer", "Finds resources shared outside the account by mistake (incl. the Databricks Unity Catalog role).", "Same", ALL, WBD),
    (R1, "1. Account foundation", "S3 Block Public Access (account level)", "Stops any S3 bucket from being made public.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "EBS encryption by default", "Makes every new disk encrypted automatically.", "Same", ALL, WBD),
    (R1, "1. Account foundation", "KMS keys", "Keys per purpose: state, ECR, RDS, S3 (+ per BU), logs, secrets, SageMaker, SQS, GenAI. No new key in v4: Glue, the optimizer task and uploads use the s3 / logs / secrets keys.", "Same", ALL, "Built - keep (no new key)"),
    (R1, "1. Account foundation", "KMS key policies", "Control which roles and AWS services can use each key; the new v4 roles get KMS access in their own IAM policies.", "Same", ALL, KEEP),
    (R1, "1. Account foundation", "S3 bucket - Terraform state", "Stores Terraform state (versioned, encrypted, S3 lock file).", "Same", ALL, KEEP),
    (R1, "1. Account foundation", "IAM permission boundary", "Attached to every Terraform-created role, incl. the new Glue, optimizer task and Databricks export Lambda roles.", "Same", ALL, KEEP),
    (R1, "1. Account foundation", "IAM OIDC identity provider (GitHub)", "Lets GitHub Actions log in to AWS without stored keys.", "Same", ALL, KEEP),
    (R1, "1. Account foundation", "IAM roles - GitHub Actions", "gha-deploy: NEW register optimizer task definitions + PassRole + ecs/* SSM pointers, dry-run input in uploads, upload Glue scripts to glue-assets + glue:GetJob(s); SageMaker optimizer pointer removed.", "Changed", ALL, "Built - change deploy role (modules/iam-oidc)"),
    (R1, "1. Account foundation", "AWS Budgets", "Alerts when spend reaches 50/80/100% of budget (Glue DPU-hours and Fargate now part of the spend).", "Same", ALL, KEEP),
    (R1, "1. Account foundation", "Cost Anomaly Detection monitor", "Alerts on unexpected spend increases.", "Same", ALL, KEEP),
    (R1, "1. Account foundation", "Amazon Macie (optional)", "Finds sensitive data stored in S3 buckets (incl. the new uploads bucket).", "Same", ALL, WBD),
    # 2. Networking
    (R1, "2. Networking", "VPC", "Private network for the environment (/19).", "Same", ALL, KEEP),
    (R1, "2. Networking", "Public subnets", "Hold the public ALB (public entry) and NAT gateways.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Private-app subnets", "ECS tasks (ui, api, NEW optimizer), Lambdas (publisher, dispatcher, NEW Databricks export), NEW Glue job ENIs, SageMaker training ENIs.", "Changed", ALL, "Built - no subnet change; new workloads only"),
    (R1, "2. Networking", "Private-data subnets", "Hold RDS PostgreSQL with no internet access.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Private-endpoint subnets", "Hold VPC interface endpoints.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Internet Gateway", "Connects public subnets to the internet (ALB also reaches the Okta token endpoint).", "Same", ALL, KEEP),
    (R1, "2. Networking", "Elastic IP (for NAT)", "Fixed public IP used by each NAT gateway (allow-listed in the Databricks workspace IP access list).", "Same", ALL, KEEP),
    (R1, "2. Networking", "NAT Gateway", "Outbound only; egress to the Databricks workspace (export Lambda) and (Release 2) LLM providers.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Route tables + associations", "Public -> IGW, app -> NAT, data/endpoint -> no internet.", "Same", ALL, KEEP),
    (R1, "2. Networking", "VPC gateway endpoints (S3, DynamoDB)", "Private, free access to S3 and DynamoDB.", "Same", ALL, KEEP),
    (R1, "2. Networking", "VPC interface endpoints", "ECR api/dkr, STS, Secrets Manager, SSM, SSM Messages, KMS, Logs, Monitoring, X-Ray, Step Functions, SageMaker API, SQS + NEW Glue.", "Changed", ALL, "Built - add glue endpoint (modules/network)"),
    (R1, "2. Networking", "Security group - VPC endpoints", "Allows HTTPS (443) from inside the VPC.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - ALB", "HTTPS from the internet or WBD ranges; egress to targets and to Okta.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - ECS ui service", "Allows traffic to UI tasks only from the ALB.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - ECS api service", "Allows traffic to API tasks only from the ALB.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - ECS one-off tasks", "No inbound; migrate and platform-check tasks; egress 443 to endpoints and S3.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - optimizer tasks", "ECS inference & optimization tasks: no inbound; 443 to the VPC endpoints and the S3 prefix list only (no DB).", "New", ALL, "Not built - add (modules/network)"),
    (R1, "2. Networking", "Security group - SageMaker jobs", "No inbound; outbound 443; now used only by training, evaluation and drift jobs.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - Glue jobs", "Self-referencing all traffic (required by Glue Spark); 443 to endpoints / S3; with the data-clients SG for RDS Proxy.", "New", ALL, "Not built - add (modules/network, with enable_data_platform)"),
    (R1, "2. Networking", "Security group - Databricks export Lambda", "No inbound; 443 out to the Databricks workspace (NAT or PrivateLink) and the VPC endpoints.", "New", ALL, "Not built - add (modules/network, with enable_data_platform)"),
    (R1, "2. Networking", "Security group - Lambda functions", "No inbound; results publisher -> RDS Proxy + endpoints; dispatcher -> endpoints.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Security group - data clients + RDS Proxy", "PostgreSQL to RDS Proxy only from the data-clients SG (API, migrate, publisher and NEW Glue jobs attach it).", "Same", ALL, "Built - keep (Glue jobs attach the data-clients SG)"),
    (R1, "2. Networking", "Security group - RDS PostgreSQL", "DB traffic only from RDS Proxy.", "Same", ALL, KEEP),
    (R1, "2. Networking", "S3 bucket - logs", "ALB access logs and S3 access logs.", "Same", ALL, KEEP),
    (R1, "2. Networking", "VPC Flow Logs", "Records network traffic for security checks.", "Same", ALL, KEEP),
    (R1, "2. Networking", "Transit Gateway attachment (optional)", "Connects the VPC to WBD's network (VDI, Splunk, Databricks).", "Same", ALL, "Built, off (enable_transit_gateway)"),
    (R1, "2. Networking", "Databricks PrivateLink endpoints (optional)", "Workspace (REST) endpoint for the export Lambda instead of the internet.", "Same", ALL, "Built, off (enable_databricks_privatelink)"),
    (R1, "2. Networking", "Route 53 private hosted zone (Databricks PrivateLink)", "Private DNS for the Databricks endpoint.", "Same", ALL, "Built, off (with PrivateLink)"),
    (R1, "2. Networking", "Route 53 Resolver outbound endpoint + rules (optional)", "Resolves WBD internal names over the Transit Gateway.", "Same", ALL, "Built, off (enable_resolver_forwarding)"),
    # 3. Container registry
    (R1, "3. Container registry", "ECR repositories", "One registry per environment: mmm/api, mmm/ui, NEW mmm/optimizer (ECS inference & optimization), mmm/sagemaker-training.", "Changed", ALL, "Built - mmm/optimizer replaces mmm/sagemaker-optimizer (modules/ecr)"),
    (R1, "3. Container registry", "ECR lifecycle policy", "Deletes old untagged images to save cost.", "Same", ALL, KEEP),
    (R1, "3. Container registry", "ECR tag immutability + enhanced scanning", "Stops tags being overwritten and scans every image.", "Same", ALL, KEEP),
    (R1, "3. Container registry", "Image promotion (pipeline step)", "Same digest copied dev -> staging -> prod on rc/release tags, incl. the optimizer image.", "Changed", ALL, "Built - repo name change in promote-images.sh"),
    # 4. Security & secrets
    (R1, "4. Security & secrets", "Secrets Manager secrets", "DB users, Okta client, Splunk, third parties, LLM keys (R2) + NEW databricks/export-sp (OAuth M2M for the export Lambda) and rds/etl (Glue DB user).", "Changed", ALL, "Built - add databricks/export-sp, rds/etl"),
    (R1, "4. Security & secrets", "SSM Parameter Store parameters", "genai_enabled, databricks/host, okta/issuer, max_concurrent_runs, token quotas, images/sagemaker-training + NEW ecs/optimizer_task_definition, databricks/export_job_ids; images/sagemaker-optimizer removed.", "Changed", ALL, "Built - add / remove parameters (main.tf, optimization.tf)"),
    # 5. Identity
    (R1, "5. Identity & login", "WBD Okta OIDC app (per environment)", "Enterprise identity provider used for authentication and RBAC; groups claim; MFA (WBD Identity team).", "Same", ALL, "WBD Identity team creates it from terraform output okta_app_settings (not Terraform)"),
    (R1, "5. Identity & login", "ALB authenticate-oidc action (Okta)", "ALB signs users in with Okta before /* reaches the UI; /api/* returns 401 when not signed in.", "Same", ALL, "Built (okta_sign_in_enabled)"),
    (R1, "5. Identity & login", "Okta groups claim -> app RBAC", "API maps mmm-bu-* / mmm-role-* groups to BU + role; PostgreSQL RLS per BU.", "Same", ALL, "Backend team (API)"),
    # 6. Data & storage
    (R1, "6. Data & storage", "S3 bucket - landing (raw data from Databricks)", "Raw data coming from Databricks: NEW raw/databricks/<bu>/<export_date>/ (Parquet + _manifest.json); 3+ years history; BU key enforced under <bu>/.", "Changed", ALL, "Built - new prefix; bucket policy allows the Unity Catalog role on raw/databricks/*"),
    (R1, "6. Data & storage", "S3 bucket - lakehouse (Delta Lake)", "Bronze / Silver / Gold Delta tables NOW written by AWS Glue + monitoring/<bu>/<date>/ (90-day expiry).", "Changed", ALL, "Built, off (enable_data_platform) - writer changes from Databricks to Glue"),
    (R1, "6. Data & storage", "S3 bucket - training data", "Immutable Parquet + metadata NOW exported by the Glue export-training job (Object Lock).", "Changed", ALL, "Built, off (enable_data_platform) - writer changes to Glue"),
    (R1, "6. Data & storage", "S3 bucket - models", "Artifacts, evaluation (predictions/, lift/, manifest), approved curves, baseline/<bu>/, monitoring/<bu>/ drift reports.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "S3 bucket - results (run outputs)", "Full run evidence of every optimization (runs/<run_id>/output), NOW written by the ECS optimizer task.", "Changed", ALL, "Built - writer changes from SageMaker to ECS"),
    (R1, "6. Data & storage", "S3 bucket - uploads (user input files)", "'S3 store user input files': inventory and future-title files under <bu>/runs/<run_id>/input/; presigned PUT from the browser, CORS = app URL only, KMS (s3 key), versioned, 90-day expiry.", "New", ALL, "Not built - add (main.tf buckets, modules/s3-bucket CORS)"),
    (R1, "6. Data & storage", "S3 bucket - glue-assets", "Glue job scripts (scripts/, uploaded by glue.yml) and Spark temp files (temp/, 7-day expiry).", "New", ALL, "Not built - add (with enable_data_platform)"),
    (R1, "6. Data & storage", "GuardDuty Malware Protection for S3 (optional)", "Scans new objects in the uploads bucket before the optimizer reads them [ASK].", "New", ALL, "Not planned by default [ASK] - client question"),
    (R1, "6. Data & storage", "S3 bucket - approved (Object Lock)", "Approved scenarios that cannot be changed.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "S3 bucket - exports", "Excel exports, auto-deleted after 30 days.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "S3 bucket policies", "HTTPS-only and deny unencrypted uploads on every bucket.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "S3 EventBridge notifications (landing bucket)", "Sends 'new file' events to EventBridge (optional refresh trigger).", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "IAM role - Databricks Unity Catalog", "NOW only write on landing raw/databricks/* (+ landing / per-BU KMS) for the export job; no lakehouse, training-data, models or monitoring access.", "Changed", ALL, "Built, off - reduce the permissions (modules/databricks-access)"),
    (R1, "6. Data & storage", "KMS keys per business unit (S3)", "BU data isolation for landing (incl. raw/databricks/<bu>/), lakehouse and training data; the Glue and export roles use them.", "Same", ALL, "Built, off (enable_data_platform) - keep"),
    (R1, "6. Data & storage", "AWS Glue Data Catalog databases", "mmm_<env>_bronze, mmm_<env>_silver, mmm_<env>_gold (Delta tables on the lakehouse bucket).", "New", ALL, "Not built - new modules/glue"),
    (R1, "6. Data & storage", "AWS Glue Data Catalog encryption settings", "Catalog metadata and connection passwords encrypted with the s3 key (account / region setting; off with manage_glue_catalog_encryption = false).", "New", ALL, "Not built - new modules/glue"),
    (R1, "6. Data & storage", "AWS Lake Formation (optional)", "Table-level grants on the Glue catalog if WBD requires them [ASK].", "New", ALL, "Not planned by default [ASK]"),
    (R1, "6. Data & storage", "DB subnet group", "Private-data subnets for RDS PostgreSQL.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "RDS DB parameter group", "rds.force_ssl, pgaudit, slow-query logging.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "RDS for PostgreSQL DB instance", "Plans, runs, allocations, audit + NEW Gold reference tables (Glue export) and model predictions, lift, evaluation (publisher). Multi-AZ in stg/prd.", "Changed", ALL, "Built - new tables via the backend's migrations; new DB user mmm_etl"),
    (R1, "6. Data & storage", "RDS read replica (optional)", "Only if reporting / QA dashboard load needs it [ASK].", "Same", PRD, "Not planned by default [ASK]"),
    (R1, "6. Data & storage", "IAM role - RDS Enhanced Monitoring", "OS metrics; Performance Insights on.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "RDS master password in Secrets Manager (auto-rotation)", "RDS creates and rotates the admin password.", "Same", ALL, KEEP),
    (R1, "6. Data & storage", "IAM role - RDS Proxy", "Lets RDS Proxy read the DB user secrets (NEW rds/etl).", "Changed", ALL, "Built - add the rds/etl secret"),
    (R1, "6. Data & storage", "RDS Proxy", "Pools connections from ECS, the publisher Lambda and NEW Glue jobs (mmm_etl) to RDS (TLS).", "Changed", ALL, "Built - add the Glue client"),
    # 7. ECS compute
    (R1, "7. ECS compute", "ECS cluster (Fargate)", "Serverless container cluster with Container Insights enhanced; now also runs the optimizer tasks (no cluster change).", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "Service Quotas increase (Fargate On-Demand vCPU)", "max_concurrent_runs x optimizer vCPU + ui / api tasks: dev >= 40, staging >= 120, prod >= 450 vCPU.", "Changed", ALL, "Manual request before the load test (now needed in every env)"),
    (R1, "7. ECS compute", "IAM role - ECS task execution", "Pulls images, writes logs and reads listed secrets (also for the optimizer).", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "IAM roles - ECS task roles", "api (NEW uploads presign read/write), ui, migrate, platform-check + NEW optimizer (read uploads, curves, registry; write results; no DB).", "Changed", ALL, "Built - change api; add optimizer"),
    (R1, "7. ECS compute", "CloudWatch log groups (per service)", "Logs per ECS service / task family with retention and KMS (NEW optimizer).", "Changed", ALL, "Built - add optimizer"),
    (R1, "7. ECS compute", "CloudWatch Logs data protection policy (optional)", "Masks personal data if it appears in logs.", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ECS task definition - migrate", "One-off task that runs DB migrations before each deploy.", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ECS task definition - api", "FastAPI + LangGraph tools (explanation tool on every run); env NEW UPLOADS_BUCKET (+ LLM_GATEWAY_URL with GenAI).", "Changed", ALL, "Built - env change (ecs.tf, ecs/<env>/api.json)"),
    (R1, "7. ECS compute", "ECS task definition - ui", "React + TypeScript web container with the QA dashboard (nginx, non-root).", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ACM certificate (project region)", "App name on the public ALB (issued by WBD).", "Same", ALL, "WBD issues it; ARN in tfvars"),
    (R1, "7. ECS compute", "Application Load Balancer (public entry)", "User-facing HTTPS entry; routes /api/* to API and /* to UI.", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ALB target groups (ip) - ui and api", "Health checks /healthz (UI) and /api/health (API).", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ALB HTTPS listener + rules", "Path routing + authenticate-oidc (Okta); HTTP -> HTTPS redirect.", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ECS service - mmm-api", "API tasks behind the ALB (circuit breaker on).", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "ECS service - mmm-ui", "UI web tasks behind the ALB (circuit breaker on).", "Same", ALL, KEEP),
    (R1, "7. ECS compute", "Application Auto Scaling policies", "CPU target 60 % for api and ui.", "Same", ALL, KEEP),
    # 8. Edge
    (R1, "8. Edge & front door", "AWS WAF web ACL (regional, on the ALB)", "Managed rules + rate limit in front of the ALB (uploads go direct to S3 with presigned URLs).", "Same", ALL, KEEP),
    (R1, "8. Edge & front door", "WAF logging configuration", "WAF logs to aws-waf-logs-* log group (-> Splunk).", "Same", ALL, KEEP),
    (R1, "8. Edge & front door", "Route 53 DNS records", "mmm-dev / mmm-stg / mmm -> ALB (WBD DNS or our zone).", "Same", ALL, "Built if route53_zone_id is set; otherwise WBD DNS adds the CNAME"),
    # 9. Optimization engine
    (R1, "9. Optimization engine", "SQS queue - optimization requests", "API sends one message per run; NEW fields run_type (optimize | forecast) and input_s3_uri in the uploads bucket.", "Changed", ALL, "Built (modules/run-queue) - contract change only"),
    (R1, "9. Optimization engine", "SQS dead-letter queue", "Messages that fail repeatedly (maxReceiveCount 10); alarm when not empty; redrive runbook.", "Same", ALL, KEEP),
    (R1, "9. Optimization engine", "Lambda function - message dispatcher", "Starts optimization executions while RUNNING < max_concurrent_runs (now bounded by the Fargate quota).", "Same", ALL, KEEP),
    (R1, "9. Optimization engine", "IAM role + log group - dispatcher", "Consume the queue, StartExecution/ListExecutions, read SSM, put metrics.", "Same", ALL, KEEP),
    (R1, "9. Optimization engine", "Lambda event source mapping (SQS -> dispatcher)", "Batch 10, maximum concurrency 2, partial batch failures.", "Same", ALL, KEEP),
    (R1, "9. Optimization engine", "ECS task definition - optimizer (inference & optimization)", "Model Summarizer, Optimizer, Simulation; Fargate 4 vCPU / 16 GB / 50 GB ephemeral (prod 8 vCPU / 32 GB) [ASM], read-only root FS, non-root; revisions registered by deploy.yml.", "New", ALL, "Not built - add (optimization.tf, ecs/<env>/optimizer.json)"),
    (R1, "9. Optimization engine", "IAM role + log group - optimizer task", "mmm-<env>-task-optimizer: read uploads, approved curves, model registry; write results/runs/*; metrics; no DB. Logs /ecs/mmm-<env>/optimizer.", "New", ALL, "Not built - add (optimization.tf)"),
    (R1, "9. Optimization engine", "SSM parameter - optimizer task definition pointer", "/mmm/<env>/ecs/optimizer_task_definition = task-definition ARN with revision (replaces the SageMaker optimizer image pointer).", "New", ALL, "Not built - replaces images/sagemaker-optimizer"),
    (R1, "9. Optimization engine", "Step Functions state machine - optimization", "ApplyDefaults -> GetOptimizerTaskDefinition -> NEW RunOptimizer (ecs:runTask.sync, Fargate, private-app, no public IP) -> publisher.", "Changed", ALL, "Built - RunOptimizer changes from SageMaker Processing to ECS RunTask"),
    (R1, "9. Optimization engine", "IAM role + log group - optimization state machine", "NEW ecs:RunTask/StopTask/DescribeTasks, PassRole (optimizer roles), events rule for .sync; invoke the publisher; logs.", "Changed", ALL, "Built - change permissions"),
    (R1, "9. Optimization engine", "ECS task - inference & optimization (runtime)", "One Fargate task per run: reads uploads + approved curves + registry, writes S3 outputs (full run evidence).", "New", ALL, "Data scientists build the image (apps/optimizer); DevOps runs it"),
    (R1, "9. Optimization engine", "Lambda function - results publisher", "Writes plans, runs and allocations from S3 outputs to RDS (alias live) + NEW model_results event (predictions, lift, evaluation).", "Changed", ALL, "Built - new event type (backend team code)"),
    (R1, "9. Optimization engine", "IAM role + log group - results publisher", "Least-privilege role (rds-db:connect via Proxy, read run output + NEW models/evaluation/*), logs.", "Changed", ALL, "Built - add read on models/evaluation/*"),
    # 10. Data & ML platform
    (R1, "10. Data & ML platform", "EventBridge Scheduler - scheduled refresh", "Starts the model-refresh state machine per BU on schedule.", "Same", ALL, "Built, off (enable_data_platform + enable_model_refresh_schedule)"),
    (R1, "10. Data & ML platform", "EventBridge rule - manual / app-triggered refresh", "mmm.refresh events from the API, operators or the drift check.", "Same", ALL, "Built, off (enable_data_platform)"),
    (R1, "10. Data & ML platform", "Databricks source catalog + export job (Jobs API)", "WBD Databricks: export of the source tables per BU to our landing raw/databricks/ prefix through a Unity Catalog external location.", "New", ALL, "WBD Databricks / data engineers - job id per BU -> SSM databricks/export_job_ids"),
    (R1, "10. Data & ML platform", "Databricks service principal (export)", "'Can manage run' on the export jobs; its OAuth client ID + secret go into secret databricks/export-sp.", "New", ALL, "WBD Databricks admins"),
    (R1, "10. Data & ML platform", "Unity Catalog storage credential + external location (landing raw/databricks/)", "Registered by the WBD Databricks admins on our IAM role (write-only).", "Changed", ALL, "WBD Databricks admins; IAM role is built - reduce to the raw/databricks/ prefix"),
    (R1, "10. Data & ML platform", "Lambda function - Databricks export (API connector)", "start: OAuth M2M token -> jobs/run-now (target URI per BU); status: jobs/runs/get; writes _manifest.json. In the VPC, egress via NAT or PrivateLink.", "New", ALL, "Not built - new (DevOps generic code, shipped by Terraform)"),
    (R1, "10. Data & ML platform", "IAM role + log group - Databricks export Lambda", "Read databricks/export-sp + SSM job ids, write landing raw/databricks/*/_manifest.json, KMS; logs.", "New", ALL, "Not built - new"),
    (R1, "10. Data & ML platform", "CloudWatch alarm - Databricks export Lambda errors", "Errors in 2 of 3 five-minute periods -> SNS (runbook databricks-export-failed).", "New", ALL, "Not built - new (modules/databricks-export)"),
    (R1, "10. Data & ML platform", "AWS Glue security configuration", "KMS for S3 output and job bookmarks (s3 key) and CloudWatch logs (logs key).", "New", ALL, "Not built - new modules/glue"),
    (R1, "10. Data & ML platform", "AWS Glue connection (NETWORK)", "Runs every job in a private-app subnet with the glue + data-clients SGs; export-rds connects to RDS Proxy as mmm_etl with an IAM token.", "New", ALL, "Not built - new modules/glue"),
    (R1, "10. Data & ML platform", "IAM role - Glue jobs", "Read landing raw/databricks/*, read/write lakehouse, write training-data, glue-assets scripts + temp, Data Catalog, DQ ruleset, rds-db:connect as mmm_etl, per-BU KMS, logs, metrics.", "New", ALL, "Not built - new"),
    (R1, "10. Data & ML platform", "CloudWatch log group - Glue jobs", "/aws-glue/jobs/mmm-<env>: continuous logging of every job (logs key).", "New", ALL, "Not built - new modules/glue"),
    (R1, "10. Data & ML platform", "Glue job scripts in glue-assets (seed + release)", "Seed placeholder that fails until glue.yml uploads the real data/glue/jobs/<job>.py.", "New", ALL, "Not built - seed by Terraform, scripts by the data engineers"),
    (R1, "10. Data & ML platform", "Service Quotas - Glue concurrent job runs / DPUs", "Six jobs x business units at the same time.", "New", ALL, "Manual request before the first full refresh"),
    (R1, "10. Data & ML platform", "AWS Glue job - bronze", "Ingest raw Parquet into Bronze Delta tables (Glue 5.0 Spark, --datalake-formats delta, bookmarks).", "New", ALL, "Not built - job by DevOps, script by the data engineers (data/glue/)"),
    (R1, "10. Data & ML platform", "AWS Glue job - silver + Data Quality ruleset", "Cleanse and validate into Silver; Glue Data Quality ruleset evaluated in the job (failure stops the refresh).", "New", ALL, "Not built - job + ruleset by DevOps, rules / script by the data engineers"),
    (R1, "10. Data & ML platform", "AWS Glue job - gold", "Per-BU modeling tables with adstock & saturation.", "New", ALL, "Not built - job by DevOps, script by the data engineers"),
    (R1, "10. Data & ML platform", "AWS Glue job - export-training", "Gold -> immutable Parquet + metadata.json in training-data/<bu>/<refresh_id>/.", "New", ALL, "Not built - job by DevOps, script by the data engineers"),
    (R1, "10. Data & ML platform", "AWS Glue job - export-rds", "Gold reference tables -> RDS PostgreSQL through RDS Proxy (mmm_etl).", "New", ALL, "Not built - job by DevOps, script by the data engineers"),
    (R1, "10. Data & ML platform", "AWS Glue job - export-monitor", "Latest features -> lakehouse/monitoring/<bu>/<date>/ for the drift check (replaces the Databricks purpose=monitor export).", "New", ALL, "Not built - job by DevOps, script by the data engineers"),
    (R1, "10. Data & ML platform", "Step Functions state machine - model refresh", "NEW: Databricks export (Lambda start/status) -> Glue bronze -> silver -> gold -> export-training + export-rds -> train -> evaluate -> register -> publish model results to RDS.", "Changed", ALL, "Built, off - replace HTTP Tasks + write-back with Lambda + Glue .sync + publisher"),
    (R1, "10. Data & ML platform", "IAM role + log group - model refresh state machine", "NEW glue:StartJobRun/GetJobRun(s)/BatchStopJobRun, lambda:InvokeFunction (export, publisher); SageMaker jobs, registry; logs.", "Changed", ALL, "Built, off - change permissions"),
    (R1, "10. Data & ML platform", "IAM roles - SageMaker training + evaluation", "Read training data, write models, register packages; drift job reads lakehouse/monitoring (now written by Glue).", "Same", ALL, "Built, off (enable_data_platform)"),
    (R1, "10. Data & ML platform", "SageMaker training job (runtime)", "Trains/tunes multi-stage models from the Parquet files; writes the drift baseline with the artifact.", "Same", ALL, "Data scientists (training image); built, off"),
    (R1, "10. Data & ML platform", "SageMaker processing job - evaluation (runtime)", "Baseline -> channel lift -> title adjustment; writes evaluation.json, curves/, predictions/, lift/ (published to RDS).", "Same", ALL, "Data scientists (training image); built, off"),
    (R1, "10. Data & ML platform", "SageMaker Model Registry - model versions", "PendingManualApproval -> Approved by model-governance.yml (publishes curves + baseline); read by the optimizer task.", "Same", ALL, "Built - keep"),
    (R1, "10. Data & ML platform", "EventBridge rule - model package state change", "Model package state changes -> SNS.", "Same", ALL, KEEP),
    (R1, "10. Data & ML platform", "Step Functions state machine - model monitor (drift)", "Per BU: NEW Databricks export + Glue bronze / silver / gold + export-monitor -> SageMaker drift job -> optional mmm.refresh when drift > threshold.", "Changed", ALL, "Built, off - export step changes from the Databricks HTTP Task to Glue .sync"),
    (R1, "10. Data & ML platform", "IAM role + log group - model monitor state machine", "NEW glue:StartJobRun (export-monitor); drift Processing jobs, PassRole, PutEvents; logs.", "Changed", ALL, "Built, off - change permissions"),
    (R1, "10. Data & ML platform", "EventBridge Scheduler - drift check", "One schedule per BU (daily; off until the first approved baseline).", "Same", ALL, "Built, off (enable_model_monitor_schedule)"),
    (R1, "10. Data & ML platform", "SageMaker processing job - drift (runtime)", "Training image with argument drift; writes drift.json and the ModelDrift metric.", "Same", ALL, "Data scientists; built, off"),
    # 11. Monitoring
    (R1, "11. Monitoring & logging", "SNS topic (alerts)", "Alarm notifications to email/Teams.", "Same", ALL, KEEP),
    (R1, "11. Monitoring & logging", "CloudWatch Container Insights", "Health and usage of ECS services and tasks (incl. optimizer tasks).", "Same", ALL, KEEP),
    (R1, "11. Monitoring & logging", "CloudWatch Application Signals (optional)", "API latency, errors and traces.", "Same", ALL, "Built, off (enable_application_signals)"),
    (R1, "11. Monitoring & logging", "CloudWatch alarms", "Existing (API, RDS, SQS/DLQ/dispatcher, drift, Step Functions, Lambda, cert, refresh overdue, GenAI); Step Functions alarms now cover the ECS optimizer runs; write-back alarm removed.", "Changed", ALL, "Built - remove write-back (modules/monitoring)"),
    (R1, "11. Monitoring & logging", "EventBridge rules -> SNS", "GuardDuty High, ECS deployment failure, break-glass, backup failed, model package state + NEW optimizer task not started (Fargate quota / image / network), Glue job failed (FAILED / TIMEOUT / ERROR), Glue Data Quality failed.", "Changed", ALL, "Built - add three rules (modules/monitoring)"),
    (R1, "11. Monitoring & logging", "CloudWatch dashboards", "Platform, api-ui, optimization (ECS tasks instead of SageMaker jobs), training, rds, cost, genai + NEW data-pipeline (export, Glue layers, DQ, rows exported).", "Changed", ALL, "Built - change optimization; add data-pipeline"),
    (R1, "11. Monitoring & logging", "Kinesis Data Firehose (to Splunk) + roles + subscription filters", "Delivers logs into WBD Splunk incl. NEW optimizer, Glue and export Lambda logs.", "Changed", ALL, "Built, off (enable_splunk_shipping) - add the new log groups"),
    (R1, "11. Monitoring & logging", "CloudWatch Synthetics canary (optional)", "Logs in and checks the app every few minutes.", "Same", STG_PRD, "Not built (gap) - deploy smoke test + optimization dry run instead"),
    # 12. Backup
    (R1, "12. Backup & DR", "RDS automated backups / PITR", "Restore the DB instance to any point in time (7/14/35 days).", "Same", ALL, KEEP),
    (R1, "12. Backup & DR", "AWS Backup vault", "Encrypted store for backups (vault lock in prod).", "Same", ALL, KEEP),
    (R1, "12. Backup & DR", "AWS Backup plan + selection", "Daily: RDS instance, results, approved, models, training data, lakehouse (uploads versioned, not backed up; glue-assets rebuilt from Git).", "Same", ALL, KEEP),
    (R1, "12. Backup & DR", "Cross-region backup copy (optional)", "Copies backups to a second region if WBD approves.", "Same", PRD, "Built, off (enable_cross_region_copy)"),
    # 13. GenAI
    (R2, "13. Release 2 - GenAI", "SSM parameters - genai_enabled flag + token quotas", "GenAI on/off without redeploy; per-BU token limits (to be sized for an explanation on every run - client question).", "Same", ALL, "Built, off (enable_genai) - no change"),
    (R2, "13. Release 2 - GenAI", "Secrets Manager - LLM provider keys", "mmm/<env>/llm/openai, anthropic, google.", "Same", ALL, "Built, off (enable_genai) - no change"),
    (R2, "13. Release 2 - GenAI", "Amazon API Gateway - LLM gateway (private REST API)", "Single entry from the API (LangGraph explanation tool, called by default for every run) to OpenAI / Anthropic / Google models.", "Same", ALL, "Built, off (enable_genai) - no change"),
    (R2, "13. Release 2 - GenAI", "Lambda - LLM proxy", "Adds the provider key and applies the guardrail to prompt and answer.", "Same", ALL, "Built, off (enable_genai) - no change"),
    (R2, "13. Release 2 - GenAI", "VPC interface endpoints - execute-api, Bedrock runtime", "Private gateway and ApplyGuardrail calls.", "Same", ALL, "Built, off (enable_genai) - no change"),
    (R2, "13. Release 2 - GenAI", "Bedrock Guardrails", "Prompt attack, PII masking/blocking, grounding checks for every provider.", "Same", ALL, "Built, off (enable_genai) - no change"),
    (R2, "13. Release 2 - GenAI", "CloudWatch alarms + dashboard - GenAI", "Gateway 4xx/5xx/latency, guardrail interventions, token quota per BU.", "Same", ALL, "Built, off (enable_genai) - no change"),
    # 14. CI/CD
    (R1, "14. CI/CD (GitHub)", "GitHub workflow - glue.yml", "Tests and uploads data/glue/jobs/<job>.py to glue-assets/scripts/ (main -> dev; dispatch -> staging / prod).", "New", ALL, "Not built - add (.github/workflows/glue.yml)"),
    (R1, "14. CI/CD (GitHub)", "GitHub workflows - optimizer-ci.yml + deploy.yml", "optimizer-ci builds mmm/optimizer; deploy registers the optimizer task revision + SSM pointer; dry run uses uploads; databricks.yml removed.", "Changed", ALL, "Built - change"),
    (R1, "14. CI/CD (GitHub)", "GitHub Environment variables", "NEW OPTIMIZER_TASK_FAMILY, OPTIMIZER_TASK_PARAM, UPLOADS_BUCKET, GLUE_ASSETS_BUCKET; DATABRICKS_CLIENT_ID removed.", "Changed", ALL, "Built - setup-github.ps1 from terraform output github_environment_variables"),
]

REMOVED = [
    ("Databricks Lakeflow refresh / feature-export job (ingestion -> Bronze -> Silver -> Gold -> Feature Export)", "AWS Glue jobs bronze / silver / gold / export-training (slide 1 'AWS Glue')", "10. Data & ML platform"),
    ("Databricks Lakeflow write-back job + model-refresh states StartDatabricksWriteback / GetWritebackRun / WritebackDone", "Results publisher Lambda writes predictions, lift and evaluation to RDS ('written in RDS')", "10. Data & ML platform"),
    ("Model-refresh states StartDatabricksJob / WaitForDatabricks / GetDatabricksRun (HTTP Tasks)", "Databricks export Lambda (start / status) + Glue startJobRun.sync", "10. Data & ML platform"),
    ("EventBridge connection (Databricks OAuth client credentials)", "Secret mmm/<env>/databricks/export-sp read by the export Lambda", "10. Data & ML platform"),
    ("Variables databricks_refresh_job_id, databricks_writeback_job_id", "SSM databricks/export_job_ids (job id per BU)", "10. Data & ML platform"),
    ("Unity Catalog external locations on lakehouse, training-data, models/evaluation/, lakehouse/monitoring/", "Write-only external location on landing raw/databricks/", "6. Data & storage"),
    ("Databricks purpose=monitor export in model-monitor", "Glue export-monitor job", "10. Data & ML platform"),
    ("databricks.yml (Asset Bundle deploy), data/databricks/, GitHub variable DATABRICKS_CLIENT_ID, setup-github.ps1 -DatabricksClientId", "glue.yml, data/glue/, GLUE_ASSETS_BUCKET", "CI/CD"),
    ("SageMaker Processing optimization job (createProcessingJob.sync) + IAM role - SageMaker optimization jobs", "ECS Fargate optimizer task via ecs:runTask.sync + optimizer task role", "9. Optimization engine"),
    ("ECR repository mmm/sagemaker-optimizer + SSM /mmm/<env>/images/sagemaker-optimizer", "ECR mmm/optimizer + SSM ecs/optimizer_task_definition", "3. Container registry"),
    ("SageMaker Processing quota for optimization runs; variable optimizer_instance_type", "Fargate vCPU quota; optimizer_cpu / optimizer_memory", "9. Optimization engine"),
    ("Runbook write-back-failed.md; write-back alarm / dashboard widgets", "Runbooks glue-job-failed.md, databricks-export-failed.md; Glue alarms + data-pipeline dashboard", "11. Monitoring & logging"),
    ("Run input under results/runs/<run_id>/input/", "uploads bucket (user input files, future titles)", "6. Data & storage"),
]

# (question, proposed default, still to confirm with WBD)
DECISIONS = [
    ("The Lambda next to Databricks on slide 1 is labelled 'Results publisher' - a separate export Lambda?", "Separate mmm-<env>-databricks-export Lambda (DevOps generic code: Jobs API run-now + runs/get); the results publisher stays the RDS writer", "Yes - architect"),
    ("How does the data leave Databricks - export job pushes to our S3, or the Lambda pulls?", "WBD export job writes Parquet to landing/raw/databricks/<bu>/<date>/ via a Unity Catalog external location on our IAM role (write-only); the Lambda starts and polls it and writes _manifest.json", "Yes - WBD Databricks"),
    ("Who owns the Databricks export job and the source catalog?", "WBD Databricks / data engineers; job id per BU in SSM databricks/export_job_ids; one service principal for the Lambda (secret databricks/export-sp)", "Yes"),
    ("AWS Glue - version, table format, sizing?", "Glue 5.0 Spark, Delta Lake on the lakehouse bucket, Data Catalog databases bronze / silver / gold; G.1X with 2 / 5 / 10 workers (dev / stg / prd); job bookmarks; 120-min timeout", "Yes - sizes after the data volumes are known"),
    ("Glue orchestration - Glue workflows / triggers or Step Functions?", "Step Functions glue:startJobRun.sync per layer inside model-refresh", "No"),
    ("AWS Lake Formation required?", "No - IAM role + bucket policies + per-BU KMS; turn on if WBD requires table-level grants", "Yes - WBD Security / Data"),
    ("How is Silver 'validated'?", "Glue Data Quality ruleset in the Silver job (rules by the data engineers); failure stops the refresh and alarms", "Yes - data team"),
    ("Glue export to RDS - which data, which DB user, direct or via RDS Proxy?", "Gold per-BU reference tables needed by the app; JDBC through RDS Proxy as mmm_etl (secret rds/etl); tables from the backend's migrations", "Yes - backend + data team"),
    ("Model predictions, lift and evaluation to RDS - which Lambda?", "Same results-publisher function, new model_results event (backend team code)", "Yes"),
    ("Optimizer on ECS - one task per run or a worker service?", "ecs:runTask.sync per run from Step Functions (isolation, simple cancel); worker service polling SQS is the alternative", "Yes"),
    ("Optimizer task size and Fargate quota?", "4 vCPU / 16 GB / 50 GB ephemeral; Fargate vCPU quota >= max_concurrent_runs x 4 + services (prod ~240)", "Yes - data science, after the load test"),
    ("max_concurrent_runs with ECS?", "Unchanged 5 / 20 / 50, now bounded by the Fargate quota", "Yes"),
    ("User input files - upload path, retention, malware scan?", "uploads bucket, presigned PUT from the API (CORS for the app domain), per-BU prefix + key, 90-day expiry, versioned, not in AWS Backup; GuardDuty Malware Protection optional (off)", "Yes - WBD Security"),
    ("'Upload future titles' - separate flow?", "New run type forecast on the same queue, state machine and optimizer image; file in uploads/<bu>/titles/", "Yes - product"),
    ("Explanation tool on every run - GenAI in Release 1?", "Stays behind enable_genai (off until WBD approves data egress or Bedrock-hosted models); the run succeeds without the explanation; ~5,000 tokens per run in the quotas", "Yes - WBD Responsible AI"),
    ("Drift inputs with Glue?", "Glue export-monitor writes lakehouse/monitoring/<bu>/<date>/; the rest of the v3 drift design is unchanged", "No"),
    ("Still open from v3", "ALB reachability / Shield Advanced; LLM data egress (more important now); Databricks IP access list (export Lambda NAT IPs); Okta groups; RDS sizes; Anthropic via Bedrock; shared account", "Yes"),
]

# Detail of what v4 introduces, for the v4_new_resources sheet.
# (layer, AWS resource, name in dev, what it is for, created by, condition, dev, staging, prod, where in the repo)
DP = "enable_data_platform"
TF = "DevOps (Terraform)"
SAME = ("same", "same", "same")
V4_NEW = [
    ("1. Networking", "VPC interface endpoint - AWS Glue", "com.amazonaws.<region>.glue", "Glue job ENIs reach the Glue API privately", TF, DP, *SAME, "modules/network (additional_interface_endpoints)"),
    ("1. Networking", "Security group - optimizer", "mmm-dev-optimizer-sg", "Optimizer ECS task: no inbound; 443 to the VPC endpoints and the S3 prefix list only", TF, "always", *SAME, "modules/network"),
    ("1. Networking", "Security group - Glue jobs", "mmm-dev-glue-sg", "Glue ENIs: all traffic within itself (Spark driver <-> executors), 443 to endpoints / S3; with data_clients for RDS Proxy", TF, DP, *SAME, "modules/network"),
    ("1. Networking", "Security group - Databricks export Lambda", "mmm-dev-databricks-export-sg", "No inbound; 443 to the Databricks workspace (NAT or PrivateLink)", TF, DP, *SAME, "modules/network"),
    ("2. Container registry", "ECR repository - mmm/optimizer", "mmm/optimizer", "Image of the inference & optimization task (Model Summarizer -> Optimizer -> Simulation); immutable tags, scan on push", TF, "always", *SAME, "modules/ecr"),
    ("3. Secrets and parameters", "Secrets Manager secret - databricks/export-sp", "mmm/dev/databricks/export-sp", "{client_id, client_secret} of the Databricks service principal (OAuth M2M); read only by the export Lambda", TF + " - value by DevOps out of band", DP, *SAME, "main.tf (secrets)"),
    ("3. Secrets and parameters", "Secrets Manager secret - rds/etl", "mmm/dev/rds/etl", "DB user mmm_etl for the Glue export-rds job (registered on RDS Proxy)", TF + " - value by db-bootstrap.py", DP, *SAME, "main.tf (secrets), scripts/db-bootstrap.py"),
    ("3. Secrets and parameters", "SSM parameter - optimizer task pointer", "/mmm/dev/ecs/optimizer_task_definition", "Task-definition ARN every run uses; written by deploy.yml (release / rollback)", TF, "always", *SAME, "optimization.tf"),
    ("3. Secrets and parameters", "SSM parameter - Databricks export job IDs", "/mmm/dev/databricks/export_job_ids", "JSON map business unit -> WBD export job ID", TF, DP, *SAME, "main.tf (parameters)"),
    ("4. Storage", "S3 bucket - uploads", "wbd-mmm-dev-uploads-<region>", "User input files (inventory, objective, future titles) under <bu>/runs/<run_id>/input/; presigned PUT from the browser, CORS = app URL only, KMS, versioned", TF, "always", "90-day expiry", "90-day expiry", "90-day expiry", "main.tf (buckets), modules/s3-bucket (CORS)"),
    ("4. Storage", "S3 bucket - glue-assets", "wbd-mmm-dev-glue-assets-<region>", "Glue job scripts (scripts/, uploaded by glue.yml) and Spark temp files (temp/, 7-day expiry)", TF, DP, *SAME, "main.tf (buckets)"),
    ("5. Optimization (ECS)", "ECS task definition - optimizer", "mmm-dev-optimizer", "One Fargate task per run (no service, no ECS Exec); revisions registered by deploy.yml from ecs/<env>/optimizer.json", TF + " + deploy.yml", "always", "4 vCPU / 16 GiB / 50 GiB", "4 vCPU / 16 GiB / 50 GiB", "8 vCPU / 32 GiB / 50 GiB", "optimization.tf, ecs/<env>/optimizer.json"),
    ("5. Optimization (ECS)", "IAM role - optimizer task", "mmm-dev-task-optimizer", "Read uploads + approved curves + model registry, write results/runs/*, metrics; no DB, no other buckets", TF, "always", *SAME, "optimization.tf"),
    ("5. Optimization (ECS)", "CloudWatch log group - optimizer", "/ecs/mmm-dev/optimizer", "Optimizer task logs (KMS, retention; Splunk when shipping is on)", TF, "always", *SAME, "modules/ecs-service"),
    ("6. Databricks export", "Lambda function - Databricks export", "mmm-dev-databricks-export", "start: OAuth token -> Jobs API 2.2 run-now; status: runs/get; writes _manifest.json; in the VPC", TF, DP, *SAME, "modules/databricks-export"),
    ("6. Databricks export", "IAM role - Databricks export Lambda", "mmm-dev-databricks-export-lambda", "Read databricks/export-sp + export_job_ids, put _manifest.json under landing raw/databricks/, BU keys, ENIs, X-Ray", TF, DP, *SAME, "modules/databricks-export"),
    ("6. Databricks export", "CloudWatch log group - export Lambda", "/aws/lambda/mmm-dev-databricks-export", "Export Lambda logs", TF, DP, *SAME, "modules/databricks-export"),
    ("6. Databricks export", "CloudWatch alarm - export Lambda errors", "mmm-dev-databricks-export-errors", "Errors in 2 of 3 five-minute periods -> SNS (runbook databricks-export-failed)", TF, DP, *SAME, "modules/databricks-export"),
    ("7. Glue lakehouse", "Glue Data Catalog databases", "mmm_dev_bronze, mmm_dev_silver, mmm_dev_gold", "Delta tables on the lakehouse bucket", TF, DP, *SAME, "modules/glue"),
    ("7. Glue lakehouse", "Glue Data Catalog encryption settings", "account / region setting", "Catalog metadata and connection passwords encrypted with the s3 key (off with manage_glue_catalog_encryption = false)", TF, DP, *SAME, "modules/glue"),
    ("7. Glue lakehouse", "Glue security configuration", "mmm-dev-glue", "KMS for S3 output, CloudWatch logs and job bookmarks", TF, DP, *SAME, "modules/glue"),
    ("7. Glue lakehouse", "Glue connection (NETWORK)", "mmm-dev-glue-vpc", "Runs the jobs in a private-app subnet with the glue + data_clients security groups", TF, DP, *SAME, "modules/glue"),
    ("7. Glue lakehouse", "IAM role - Glue jobs", "mmm-dev-glue", "Read landing raw/, read / write lakehouse, write training-data, glue-assets scripts + temp, catalog, DQ ruleset, rds-db:connect as mmm_etl", TF, DP, *SAME, "modules/glue"),
    ("7. Glue lakehouse", "CloudWatch log group - Glue jobs", "/aws-glue/jobs/mmm-dev", "Continuous logging of every job (logs key)", TF, DP, *SAME, "modules/glue"),
    ("7. Glue lakehouse", "Glue Data Quality ruleset - silver", "mmm-dev-silver", "DQDL rules evaluated by the silver job; a failure stops the refresh", TF + " - rules by the data engineers", DP, *SAME, "modules/glue, data/glue/dq/silver.dqdl"),
    ("7. Glue lakehouse", "Glue job - bronze", "mmm-dev-glue-bronze", "Raw Databricks Parquet -> Bronze Delta (job bookmarks)", TF + " - script by the data engineers", DP, "G.1X x 2", "G.1X x 5", "G.1X x 10", "modules/glue, data/glue/jobs/bronze.py"),
    ("7. Glue lakehouse", "Glue job - silver", "mmm-dev-glue-silver", "Cleanse, conform, Data Quality", TF + " - script by the data engineers", DP, "G.1X x 2", "G.1X x 5", "G.1X x 10", "modules/glue, data/glue/jobs/silver.py"),
    ("7. Glue lakehouse", "Glue job - gold", "mmm-dev-glue-gold", "Per-BU modeling tables (adstock, saturation)", TF + " - script by the data engineers", DP, "G.1X x 2", "G.1X x 5", "G.1X x 10", "modules/glue, data/glue/jobs/gold.py"),
    ("7. Glue lakehouse", "Glue job - export-training", "mmm-dev-glue-export-training", "Gold -> immutable Parquet snapshot in training-data/<bu>/<refresh_id>/", TF + " - script by the data engineers", DP, "G.1X x 2", "G.1X x 5", "G.1X x 10", "modules/glue"),
    ("7. Glue lakehouse", "Glue job - export-rds", "mmm-dev-glue-export-rds", "Gold reference tables -> RDS PostgreSQL through RDS Proxy as mmm_etl (IAM token)", TF + " - script by the data engineers", DP, "G.1X x 2", "G.1X x 5", "G.1X x 10", "modules/glue"),
    ("7. Glue lakehouse", "Glue job - export-monitor", "mmm-dev-glue-export-monitor", "Latest features -> lakehouse/monitoring/<bu>/<date>/ for the drift check", TF + " - script by the data engineers", DP, "G.1X x 2", "G.1X x 5", "G.1X x 10", "modules/glue"),
    ("7. Glue lakehouse", "Glue seed scripts", "s3://<glue-assets>/scripts/<job>.py", "Placeholder that stops with an error until glue.yml uploads the real script", TF, DP, *SAME, "modules/glue"),
    ("8. Monitoring", "EventBridge rule - optimizer task not started", "mmm-dev-optimizer-task-not-started", "Optimizer task stopped with TaskFailedToStart (Fargate quota, image pull, network) -> SNS", TF, "always", *SAME, "modules/monitoring"),
    ("8. Monitoring", "EventBridge rule - Glue job failed", "mmm-dev-glue-job-failed", "A Glue job ended FAILED / TIMEOUT / ERROR -> SNS", TF, DP, *SAME, "modules/monitoring"),
    ("8. Monitoring", "EventBridge rule - Glue Data Quality failed", "mmm-dev-glue-data-quality-failed", "Silver ruleset failed -> SNS", TF, DP, *SAME, "modules/monitoring"),
    ("8. Monitoring", "CloudWatch dashboard - data pipeline", "mmm-dev-data-pipeline", "Glue job time / failed tasks / records, export Lambda invocations / errors / duration, refresh executions", TF, DP, *SAME, "modules/monitoring"),
    ("9. CI/CD", "GitHub workflow - glue.yml", "glue", "Uploads data/glue/jobs/<job>.py to glue-assets/scripts/ (main -> dev; dispatch -> staging / prod)", "DevOps (GitHub Actions)", DP, *SAME, ".github/workflows/glue.yml"),
    ("9. CI/CD", "GitHub Environment variables", "OPTIMIZER_TASK_FAMILY, OPTIMIZER_TASK_PARAM, UPLOADS_BUCKET, GLUE_ASSETS_BUCKET", "deploy.yml (optimizer revision, dry run) and glue.yml", "DevOps (setup-github.ps1)", "always (GLUE_ASSETS_BUCKET with the data platform; UPLOADS_BUCKET dev / staging)", *SAME, "outputs.tf github_environment_variables"),
    ("10. Outside this repo (needed for v4)", "Databricks export job per business unit", "WBD workspace", "Writes the source tables as Parquet to landing raw/databricks/<bu>/<id>/ (job parameters business_unit, output_uri, purpose, request_id)", "WBD Databricks", DP, *SAME, "data/README.md (contract)"),
    ("10. Outside this repo (needed for v4)", "Databricks service principal (export)", "WBD workspace", "'Can manage run' on the export jobs; OAuth secret goes into databricks/export-sp", "WBD Databricks", DP, *SAME, "docs/10 §4"),
    ("10. Outside this repo (needed for v4)", "Unity Catalog external location on landing raw/databricks/", "WBD workspace", "On the storage credential for our write-only IAM role mmm-dev-databricks-uc", "WBD Databricks", DP, *SAME, "docs/10 §4"),
    ("10. Outside this repo (needed for v4)", "Service Quotas - Fargate On-Demand vCPU", "account quota", "max_concurrent_runs x optimizer vCPU + api / ui tasks", "WBD Cloud Platform", "always", ">= 40", ">= 120", ">= 450", "docs/runbooks/scale-planning-season.md"),
    ("10. Outside this repo (needed for v4)", "Service Quotas - Glue concurrent job runs / DPUs", "account quota", "Six jobs x business units at the same time", "WBD Cloud Platform", DP, *SAME, "docs/runbooks/scale-planning-season.md"),
    ("10. Outside this repo (needed for v4)", "Glue job scripts and Silver DQ rules", "data/glue/jobs/, data/glue/dq/", "bronze, silver, gold, export-training, export-rds, export-monitor", "Data engineers", DP, *SAME, "data/README.md"),
    ("10. Outside this repo (needed for v4)", "Optimizer image", "apps/optimizer", "Reads INPUT_S3_URI + CURVES_S3_URI, writes OUTPUT_S3_URI, RUN_TYPE optimize / forecast, DRY_RUN", "Data science", "always", *SAME, "docs/09 §5"),
]

# Existing (v1-v3) resources that v4 modifies - nothing else from v1-v3 is listed.
V4_CHANGED = [
    ("Networking", "VPC interface endpoints", "Adds glue (above)"),
    ("Storage", "S3 bucket - landing", "Unity Catalog role may write raw/databricks/ only; bucket policy requires the BU key under raw/databricks/<bu>/ too"),
    ("Storage", "S3 bucket - lakehouse / training-data", "Writer is now AWS Glue (was Databricks)"),
    ("Storage", "S3 bucket - results", "Written by the ECS optimizer task (was SageMaker); input files moved to uploads"),
    ("Identity", "IAM role - Databricks Unity Catalog (mmm-dev-databricks-uc)", "Reduced to write-only on landing raw/databricks/ (no lakehouse, training-data, models)"),
    ("Identity", "IAM role - GitHub deploy (mmm-dev-gha-deploy)", "Register optimizer task revisions, PassRole, write ecs/* SSM pointers, uploads dry-run input, glue-assets scripts/* + glue:GetJob(s)"),
    ("Identity", "IAM role - API task", "Put / get objects in uploads (presigned URLs); env UPLOADS_BUCKET"),
    ("Identity", "IAM role - platform-check task", "Reads the release pointers (optimizer task, training image)"),
    ("Database", "RDS Proxy", "Adds the rds/etl secret (mmm_etl, Glue export-rds)"),
    ("Database", "RDS PostgreSQL", "New DB user mmm_etl (db-bootstrap.py); new tables from the backend migrations (Gold reference data, model results)"),
    ("Optimization", "Step Functions - mmm-dev-optimization", "RunOptimizer = ecs:runTask.sync (was SageMaker Processing); reads the optimizer task pointer; run_type optimize / forecast"),
    ("Optimization", "Lambda - results publisher (+ role)", "New event model_results; reads models/evaluation/*"),
    ("Data platform", "Step Functions - mmm-dev-model-refresh", "Export Lambda -> Glue bronze / silver / gold -> export-training + export-rds -> train -> evaluate -> register -> PublishModelResults (was Databricks HTTP Tasks + write-back)"),
    ("Data platform", "Step Functions - mmm-dev-model-monitor", "Export + Glue medallion + export-monitor before the drift check"),
    ("Monitoring", "Dashboard - optimization", "ECS optimizer task widgets (were SageMaker jobs)"),
    ("Monitoring", "Splunk subscription filters", "Adds optimizer, glue-jobs and databricks-export log groups"),
    ("CI/CD", "deploy.yml, optimizer-ci.yml, dry run", "Optimizer = ECS task revision + SSM pointer; dry-run input in uploads"),
]

YELLOW = PatternFill("solid", fgColor="FFF2CC")
GREEN = PatternFill("solid", fgColor="E2EFDA")
GREY = PatternFill("solid", fgColor="E7E6E6")
HEAD = PatternFill("solid", fgColor="1F3864")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
NOT_DEVOPS = ("WBD", "Not planned", "Manual", "Data scientists", "Backend team", "Data engineers")


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


DATA_PLATFORM_HINTS = ("Glue", "Databricks", "glue-assets", "Unity Catalog", "model refresh", "model monitor", "drift",
                       "SageMaker", "Model Registry", "lakehouse", "training data", "per business unit")


def build_status(layer, res, change, action):
    if action.startswith("Manual"):
        return "Quota request by WBD Cloud Platform"
    if action.startswith("Not planned"):
        return "Not built - open decision (client question)"
    if action.startswith(NOT_DEVOPS):
        return "Owned by WBD / another team"
    if action.startswith("Not built (gap)"):
        return "Gap - not built (unchanged from v3)"
    if change == "Same":
        return "Built in v1-v3 - no v4 change"
    flag = re.match(r"Built, off \(([a-z_]+)", action)
    if flag:
        return f"Implemented - created with {flag.group(1)}"
    on_flag = layer.startswith("10.") or any(h in res for h in DATA_PLATFORM_HINTS)
    return "Implemented - created with enable_data_platform" if on_flag else "Implemented"


def full_sheet(wb, env):
    ws = wb.create_sheet(env)
    ws["A1"] = (f"WBD MMM - {env.capitalize()} - all AWS resources for the v4 architecture in creation order "
                "(WBD_MMM_Architecture_4.pptx)")
    ws["A1"].font = Font(bold=True, size=13)
    ws["A2"] = ("Full list for requirement 4 (v1-v3 resources that v4 still needs + what v4 adds). Step numbers match across Dev, "
                "Staging and Prod. Yellow = new in v4, green = changed by v4, no colour = kept from v1-v3, grey = owned by WBD or "
                "another team. Resources v4 removed are on 'removed_vs_v3'; the v4-only detail (names, sizes, repo location) is on "
                "'v4_new_resources'. Status 12 Nov 2026: implemented and validated offline, nothing applied to AWS yet.")
    ws["A2"].font = Font(italic=True, size=9)
    ws.append([])
    ws.append(["Step", "Release", "Layer", "AWS Resource", "Description", "Change vs v3", "v4 action (owner / where)",
               "v4 build status (12 Nov 2026)"])
    header_row(ws, 4)
    for step, (rel, layer, res, desc, change, envs, action) in enumerate(ROWS, 1):
        if env not in envs:
            continue
        ws.append([step, rel, layer, res, desc, change, action, build_status(layer, res, change, action)])
        fill = GREY if action.startswith(NOT_DEVOPS) else YELLOW if change == "New" else GREEN if change == "Changed" else None
        body_row(ws, fill)
    for col, w in zip("ABCDEFGH", (6, 10, 24, 46, 80, 12, 56, 40)):
        ws.column_dimensions[col].width = w
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A4:H{ws.max_row}"


def build_xlsx():
    wb = Workbook()
    wb.remove(wb.active)
    for env in ALL:
        full_sheet(wb, env)

    ws = wb.create_sheet("summary")
    ws["A1"] = "Resource count per layer (rows on the dev / staging / prod sheets)"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["Layer", "Resources", "Dev", "Staging", "Prod", "New in v4", "Changed by v4", "Kept from v1-v3"])
    header_row(ws, 3)
    for layer in dict.fromkeys(r[1] for r in ROWS):
        rows = [r for r in ROWS if r[1] == layer]
        ws.append([layer, len(rows), *(sum(1 for r in rows if e in r[5]) for e in ALL),
                   sum(1 for r in rows if r[4] == "New"), sum(1 for r in rows if r[4] == "Changed"),
                   sum(1 for r in rows if r[4] == "Same")])
        body_row(ws)
    ws.append(["Total", len(ROWS), *(sum(1 for r in ROWS if e in r[5]) for e in ALL),
               sum(1 for r in ROWS if r[4] == "New"), sum(1 for r in ROWS if r[4] == "Changed"),
               sum(1 for r in ROWS if r[4] == "Same")])
    body_row(ws)
    for c in ws[ws.max_row]:
        c.font = Font(bold=True)
    ws.append(["Removed vs v3", len(REMOVED)])
    body_row(ws)
    for col, w in zip("ABCDEFGH", (30, 11, 8, 9, 8, 11, 14, 15)):
        ws.column_dimensions[col].width = w

    ws = wb.create_sheet("v4_new_resources")
    ws["A1"] = ("WBD MMM - AWS resources created for requirement 4 only (WBD_MMM_Architecture_4.pptx: ECS inference & optimization, "
                "user uploads, Databricks source export, AWS Glue lakehouse)")
    ws["A1"].font = Font(bold=True, size=13)
    ws["A2"] = ("Detail of what v4 adds (the full list incl. the v1-v3 resources v4 still needs is on the dev / staging / prod sheets; "
                "existing ones that v4 modifies are on 'v4_changes'). "
                "Names are for dev (staging mmm-stg-*, prod mmm-prd-*). Condition 'enable_data_platform' = created when the data platform is on. "
                "Grey = owned by WBD or another team. Status 12 Nov 2026: implemented in the repo, nothing applied to AWS yet.")
    ws["A2"].font = Font(italic=True, size=9)
    ws.append([])
    ws.append(["#", "Layer", "AWS resource", "Name (dev)", "What it is for", "Created by", "Condition",
               "Dev", "Staging", "Prod", "Where in the repo"])
    header_row(ws, 4)
    for i, row in enumerate(V4_NEW, 1):
        ws.append([i, *row])
        body_row(ws, None if row[4].startswith("DevOps") else GREY)
    for col, w in zip("ABCDEFGHIJK", (5, 22, 40, 34, 70, 28, 20, 16, 16, 16, 40)):
        ws.column_dimensions[col].width = w
    ws.freeze_panes = "A5"
    ws.auto_filter.ref = f"A4:K{ws.max_row}"

    ws = wb.create_sheet("v4_changes")
    ws["A1"] = "Existing resources (from v1-v3) that requirement 4 modifies"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["#", "Layer", "Existing resource", "What v4 changes"])
    header_row(ws, 3)
    for i, row in enumerate(V4_CHANGED, 1):
        ws.append([i, *row])
        body_row(ws)
    for col, w in zip("ABCD", (5, 18, 50, 100)):
        ws.column_dimensions[col].width = w
    ws.freeze_panes = "A4"

    ws = wb.create_sheet("removed_vs_v3")
    ws["A1"] = "v3 resources (built in the repo) that are not in the v4 architecture - removed by the v4 build"
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(["#", "Layer", "Removed resource", "Replaced by / reason"])
    header_row(ws, 3)
    for i, (res, why, layer) in enumerate(REMOVED, 1):
        ws.append([i, layer, res, why])
        body_row(ws)
    for col, w in zip("ABCD", (5, 24, 70, 70)):
        ws.column_dimensions[col].width = w
    wb.save(OUT / "aws_resource_list_4.xlsx")


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
    p("DevOps Implementation Plan v4 - Hybrid Lakehouse + MLOps on AWS (AWS Glue + SageMaker + ECS Fargate inference & optimization, "
      "Databricks source export, Okta SSO, RDS PostgreSQL, SQS dispatch)", None).runs[0].bold = True
    note = p("Version 4 of wbd_mmm_ecs_final_3.docx, updated for the client architecture in WBD_MMM_Architecture_4.pptx "
             "(slide 1: auto ML activities; slide 2: optimization and explainable planning). v3 is built in the repo; "
             "this document is the v4 plan (12 Nov 2026), not implemented yet. Items marked [ASK] / [ASM] have the proposed "
             "default in section 10.")
    note.runs[0].italic = True
    note.runs[0].font.color.rgb = RGBColor(0x59, 0x59, 0x59)

    h("1. What changed vs v3")
    table(["Area", "v3 (built)", "v4 (client architecture)", "DevOps impact"], [
        ("Data engineering", "Databricks Lakeflow Jobs: ingestion -> Bronze -> Silver -> Gold -> Feature Export", "AWS Glue: Bronze -> Silver (cleansed, validated) -> Gold; Delta Lake on S3", "New glue module (catalog, jobs, Data Quality, connections, role); glue endpoint + SG; glue.yml"),
        ("Source data", "Files in S3 landing, ingested by Databricks", "Databricks source catalog exported via Jobs APIs by a Lambda (Databricks API connector) to S3", "New Databricks export Lambda + secret; Unity Catalog role reduced to write on raw/databricks/"),
        ("Glue exports", "Feature Export -> training data", "Gold -> training data, Gold -> RDS PostgreSQL, layers -> Delta Lake", "Glue export jobs; JDBC to RDS Proxy (mmm_etl)"),
        ("Model results", "Databricks write-back job -> Gold", "Lambda results publisher -> RDS ('written in RDS')", "Remove write-back states / job / runbook; publisher model_results event"),
        ("Optimization engine", "SageMaker Processing job", "ECS Inference and Optimization Fargate container", "Optimizer task definition + role; Step Functions ecs:runTask.sync; ECR mmm/optimizer; Fargate quota"),
        ("User input files", "Run input in results/runs/<id>/input", "S3 'store user input files'; upload inventory or future titles", "New uploads bucket (presigned, per-BU key, expiry); run_type in the message"),
        ("GenAI", "Release 2, optional", "Explanation tool by default for every run; 'with GenAI capabilities'", "Token quotas per run; gateway sizing; Release 1 or 2 to confirm"),
        ("Wording", "Operations; QA dashboard in the API", "Logging/Operations; QA dashboard in the UI; Okta for authentication and RBAC", "None"),
    ])

    h("2. Target platform")
    p("The WBD MMM application (UI + API) and the inference & optimization engine run on Amazon ECS with AWS Fargate in three "
      "WBD-owned AWS accounts (Dev, Stage, Prod). Planners sign in with WBD Okta at the public Application Load Balancer (behind "
      "AWS WAF). Plans, runs, allocations, Gold reference data and model results live in RDS for PostgreSQL. Optimization requests "
      "are buffered in Amazon SQS and started by a Lambda dispatcher as AWS Step Functions executions that run one ECS Fargate task "
      "per run inside the VPC. Source data is exported from the WBD Databricks source catalog into S3; AWS Glue builds the Bronze / "
      "Silver / Gold Delta Lake layers on S3 and exports training data and reference data; SageMaker trains, evaluates and "
      "registers the models and checks model drift.", "Decision: ")
    p("Terraform - GitHub Actions (OIDC) - Amazon ECR - Amazon ECS on Fargate + ALB - Route 53 - AWS WAF - ACM - WBD Okta (OIDC) - "
      "RDS for PostgreSQL (+ RDS Proxy) - Amazon SQS - AWS Lambda - AWS Step Functions - AWS Glue (jobs, Data Catalog, Data Quality) - "
      "Amazon SageMaker (training, Model Registry, drift checks) - S3 (raw landing, Delta Lake, training data, models, uploads, Glue "
      "assets, results, exports, Object Lock) - KMS - Secrets Manager + Parameter Store - Amazon EventBridge (+ Scheduler) - "
      "Databricks (source catalog, export job) - Amazon API Gateway - Amazon Bedrock Guardrails - CloudWatch + CloudTrail - AWS Backup.",
      "Platform stack: ")
    p("React + TypeScript - Python / FastAPI - scikit-learn / XGBoost / LangGraph - SciPy - RDS PostgreSQL + "
      "Databricks / S3 - ECS - AWS recommended.", "Prescribed stack (WBD): ")

    h("3. Application components and runtimes")
    table(["Component", "Runs on", "What it does", "How it scales"], [
        ("mmm-ui", "ECS Fargate", "React + TypeScript web container with the QA dashboard", "CPU target tracking; Dev 1-2, Stage 2-3, Prod 2-6 tasks"),
        ("mmm-api", "ECS Fargate", "FastAPI + LangGraph tools (explanation tool on every run); what-if; presigned uploads; queues runs", "CPU target tracking; Dev 1-2, Stage 2-4, Prod 3-10"),
        ("mmm-migrate", "ECS Fargate (one-off)", "Alembic DB migration before each deploy", "Once per deploy"),
        ("Run queue", "Amazon SQS (+ DLQ)", "Buffers optimization / forecast requests from 50-150 planners", "Unlimited; age and DLQ alarms"),
        ("Message dispatcher", "AWS Lambda (VPC)", "Starts executions while RUNNING < max_concurrent_runs", "Max concurrency 2"),
        ("Optimization workflow", "Step Functions (Standard)", "Async run: ECS optimizer task -> publisher, retries, timeouts", "One execution per run id"),
        ("Inference & optimization", "ECS Fargate task (one per run)", "Model Summarizer, Optimizer, Simulation", "<= max_concurrent_runs at a time (Fargate quota)"),
        ("Results publisher", "AWS Lambda (VPC)", "Writes run results and model results (predictions, lift, evaluation) to RDS", "Per run / refresh"),
        ("Databricks export", "AWS Lambda (VPC)", "Starts and polls the Databricks export job (Jobs API)", "Per refresh per BU"),
        ("Bronze / Silver / Gold + exports", "AWS Glue Spark jobs", "Raw -> cleansed + validated -> per-BU modeling tables; exports to training data, RDS, monitoring", "Workers per job (2 / 5 / 10)"),
        ("Model refresh workflow", "Step Functions + EventBridge", "Export -> Glue layers -> train -> evaluate -> publish to RDS -> register", "Scheduled / manual / app-triggered"),
        ("Model monitor workflow", "Step Functions + Scheduler", "Glue monitor export -> drift job -> alarm / optional refresh", "Daily per BU"),
        ("Training, evaluation, drift", "SageMaker training / processing jobs", "Multi-stage models; baseline, channel lift, title adjustment; drift", "Per refresh / check"),
        ("LLM gateway", "Amazon API Gateway (+ Lambda)", "OpenAI / Anthropic / Google models; Bedrock Guardrails", "Stage throttling; BU quotas in the API"),
    ])

    h("4. The two flows")
    h("4.1 Auto ML activities (slide 1)", 2)
    bullets([
        "Scheduled refresh (EventBridge Scheduler), manual or application-triggered refresh -> EventBridge -> Step Functions (schedule / manual, wait / retry).",
        "NEW: Step Functions invokes the Databricks export Lambda, which uses the Databricks API connector (Jobs API, OAuth service principal) to run the export job in the Databricks source catalog.",
        "NEW: the export job writes the raw data (3+ years of historical inventory) to S3 (landing raw/databricks/<bu>/<date>/).",
        "NEW: AWS Glue builds Bronze (ingested raw) -> Silver (cleansed and validated, Glue Data Quality) -> Gold (per-BU modeling tables, adstock & saturation) as Delta tables on S3 (Delta Lake storage).",
        "NEW: Glue exports Gold to the training-data bucket (immutable Parquet + metadata) and to RDS PostgreSQL (reference data for the app).",
        "SageMaker modeling in the VPC: training (multi-stage) -> evaluation (baseline -> channel lift -> title adjustment) -> model registration (PendingManualApproval).",
        "NEW: the Lambda results publisher writes the model predictions, lift and evaluation results to RDS for the corresponding dataset (no write-back to Databricks).",
        "A named WBD approver approves the version (model-governance.yml); approved response curves and the drift baseline are published to S3; model drift monitoring runs per BU on a schedule (monitor export now from Glue).",
    ])
    h("4.2 Optimization and explainable planning (slide 2)", 2)
    bullets([
        "Planner uploads inventory, chooses an objective, runs and compares - NEW or uploads future titles -> DNS / WAF -> ALB (HTTPS, public entry) -> Okta sign-in (authentication + RBAC).",
        "ECS UI (web + QA dashboard) -> ECS API (FastAPI with LangGraph tools; NEW explanation tool invoked by default for every run) <-> RDS PostgreSQL (plans, runs, allocations).",
        "NEW: the API stores user input files in S3 (uploads bucket, presigned upload).",
        "The API stores the run as QUEUED and sends a message to SQS; the Lambda message dispatcher starts the Step Functions execution when capacity is free.",
        "NEW: Step Functions (async) runs the ECS Inference and Optimization Fargate task (Model Summarizer, Optimizer, Simulation), which reads the approved model (SageMaker Registry), the approved response curves (S3) and the user input files.",
        "S3 outputs (full run evidence) -> Lambda results publisher -> RDS PostgreSQL.",
        "API -> Amazon API Gateway -> OpenAI / Anthropic / Google models, with Amazon Bedrock Guardrails.",
        "Sized for 50-150 planners working at the same time in planning seasons; the queue absorbs bursts within the Fargate quota.",
    ])

    h("5. Deployment approach - Flywheel pattern on AWS (updated)")
    table(["Flywheel (Azure)", "WBD MMM v4 (AWS)"], [
        ("Container Apps Environment", "ECS cluster (Fargate)"),
        ("Container App + revision", "ECS service (ui, api) + task definition revision"),
        ("Container App Job", "ECS Fargate task per run via SQS -> dispatcher -> Step Functions (optimizer); ECS one-off task (migration)"),
        ("Built-in ingress + managed certificate", "Public ALB + ACM + regional WAF; Route 53"),
        ("Entra ID login", "WBD Okta (OIDC at the ALB)"),
        ("Azure Container Registry", "Amazon ECR (per env, digest promotion)"),
        ("Key Vault", "Secrets Manager / Parameter Store"),
        ("Service Bus / Storage queue", "Amazon SQS (+ DLQ)"),
        ("Data Factory / Synapse Spark", "AWS Glue (Spark jobs, Data Catalog, Data Quality)"),
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
        ("A", "Lambda pulls the data from Databricks (SQL Statement Execution API, external links) instead of the export job pushing to S3", "No cross-account role; but Lambda time / memory limits for 3+ years of history"),
        ("B", "Glue workflows / triggers instead of Step Functions orchestration", "Native to Glue; but two orchestrators and separate retries / alarms"),
        ("C", "AWS Lake Formation on the Glue catalog", "Table / column-level grants and audit; more setup"),
        ("D", "ECS worker service polling SQS (scales on queue depth) instead of one RunTask per run", "Saves task start-up (~30-60 s); less isolation, more complex cancel"),
        ("E", "Separate model-results publisher Lambda instead of a new event type on the results publisher", "Least privilege per writer; one more function to deploy"),
        ("F", "GuardDuty Malware Protection for S3 on uploads", "Scans user files before use; extra cost per GB"),
        ("G", "Bedrock-hosted models (e.g. Anthropic via Bedrock) for the explanation tool", "Keeps prompts and data inside AWS, which matters more now that every run calls the LLM"),
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
        ("Optimizer task [ASM]", "4 vCPU / 16 GB", "4 vCPU / 16 GB", "4 vCPU / 16 GB (sized from the load test)"),
        ("max_concurrent_runs [ASM]", "5", "20", "50 (<= Fargate quota)"),
        ("Fargate vCPU quota [ASM]", ">= 30", ">= 100", ">= 240"),
        ("Glue workers per job [ASM]", "2 x G.1X", "5 x G.1X", "10 x G.1X"),
        ("RDS PostgreSQL [ASM]", "db.t4g.medium, single-AZ", "db.r6g.large, Multi-AZ", "db.r6g.xlarge, Multi-AZ, deletion protection"),
        ("SageMaker training instance", "ml.m5.2xlarge", "Prod-like for performance tests", "Sized from the load test"),
        ("Backups", "PITR 7 d", "PITR 14 d + AWS Backup + restore tests", "PITR 35 d, vault lock, cross-region if approved"),
        ("Log retention", "30 days", "90 days", "365 days (+ Splunk)"),
        ("Data allowed", "Synthetic / masked", "Approved prod-like clone", "Production"),
        ("Deployment approval", "Automatic", "EY lead", "WBD approver + change ticket"),
    ])

    h("8. Stages at a glance")
    table(["Stage", "Name", "Main output (v4 change)"], [
        ("0", "Access", "Logins to GitHub, AWS, Databricks (export SP), Okta admin contact"),
        ("1", "Questions for the client", "v4 questions (section 10, devops_4_client_question.xlsx)"),
        ("2", "Design and approval", "Approved v4 design pack"),
        ("3", "Account foundation", "Deploy role: optimizer task definitions, Glue scripts; boundary on the new roles"),
        ("4", "Networking", "Glue endpoint + SG; RDS Proxy from Glue"),
        ("5", "Security baseline + identity", "Secrets databricks/export-sp, rds/etl; SSM optimizer pointer, export job ids"),
        ("6", "Data & storage", "uploads and glue-assets buckets; Glue Data Catalog; mmm_etl DB user"),
        ("7", "ECS on Fargate", "API uploads role / env; optimizer task definition"),
        ("8", "Docker", "mmm/optimizer (ECS) replaces mmm/sagemaker-optimizer"),
        ("9", "Optimization engine", "Step Functions ecs:runTask.sync; SageMaker optimization job removed"),
        ("10", "Data & ML platform", "Databricks export Lambda; Glue jobs; refresh publishes model results to RDS; monitor export via Glue"),
        ("11", "CI/CD", "optimizer-ci (ECS), deploy.yml optimizer revision + Glue scripts, glue.yml; databricks.yml removed"),
        ("12", "Front door and login", "Unchanged"),
        ("13", "Logging and monitoring", "Glue, DQ, export, optimizer task alarms; data-pipeline dashboard"),
        ("14", "Backup and DR", "Unchanged selection"),
        ("15", "Testing and Release 1 go-live", "End-to-end Glue refresh, optimizer start time, queue load test with Fargate quota, uploads"),
        ("16", "Release 2 - GenAI", "Explanation tool on every run (or in Release 1 if WBD approves)"),
        ("17", "Handover and operations", "glue-job-failed, databricks-export-failed runbooks; write-back-failed removed"),
    ])

    h("9. Stages")
    stages = [
        ("Stage 0 - Access", ["Access to GitHub, AWS (SSO + CLI), the Databricks workspace (export job, service principal), SageMaker, Splunk, CloudWatch.",
                              "Contacts: WBD Cloud Platform, Network, Identity (Okta), Databricks admins, Data Science lead, Data Engineering, InfoSec, CAB."]),
        ("Stage 1 - Questions for the client", ["All v3 questions except the Databricks refresh / write-back jobs, plus the v4 questions in section 10 (Databricks export, Glue sizing and Lake Formation, optimizer task size and Fargate quota, uploads, GenAI on every run)."]),
        ("Stage 2 - Design and approval", ["Deployment diagram from WBD_MMM_Architecture_4.pptx with network detail.",
                                           "ADRs: Glue instead of Databricks Lakeflow, Databricks export by Jobs API, ECS instead of SageMaker for optimization, model results in RDS, uploads bucket, explanation on every run."]),
        ("Stage 3 - Account foundation", ["KMS keys unchanged (Glue uses s3 + logs); permission boundary on the Glue, optimizer and export roles; deploy role registers optimizer task definitions and uploads Glue scripts."]),
        ("Stage 4 - Networking", ["Unchanged subnets; add the Glue interface endpoint; Glue SG (self-referencing) with 5432 to RDS Proxy; optimizer tasks use the tasks SG; export Lambda uses the Lambda SG (Databricks via NAT or PrivateLink)."]),
        ("Stage 5 - Security baseline and identity", ["Okta unchanged (authentication + RBAC).",
                                                       "Secrets databricks/export-sp and rds/etl; SSM ecs/optimizer_task_definition and databricks/export_job_ids; SSM images/sagemaker-optimizer removed."]),
        ("Stage 6 - Data & storage", ["New uploads bucket (presigned PUT, CORS, per-BU key, 90-day expiry) and glue-assets bucket; landing raw/databricks/ prefix; lakehouse and training data written by Glue.",
                                      "Glue Data Catalog databases bronze / silver / gold; RDS user mmm_etl through RDS Proxy; Gold reference and model-result tables in the backend's migrations."]),
        ("Stage 7 - ECS on Fargate", ["API task role: read / write uploads (presigned); env UPLOADS_BUCKET (+ LLM_GATEWAY_URL with GenAI).",
                                      "Optimizer task definition (4 vCPU / 16 GB [ASM]) and task role (read uploads, curves, registry; write results; no DB)."]),
        ("Stage 8 - Docker", ["mmm/ui, mmm/api, NEW mmm/optimizer (ECS inference & optimization), mmm/sagemaker-training."]),
        ("Stage 9 - Optimization engine", ["SQS + DLQ + dispatcher unchanged (contract adds run_type, input in uploads).",
                                           "Optimization state machine: RunOptimizer = ecs:runTask.sync (Fargate, private-app, no public IP, container overrides per run); SageMaker optimization job, role, image pointer and quota removed."]),
        ("Stage 10 - Data & ML platform", ["Databricks export Lambda (Jobs API run-now / runs/get) + Unity Catalog role write-only on raw/databricks/.",
                                           "Glue jobs bronze, silver (+ Data Quality), gold, export-training, export-rds, export-monitor with security configuration and connections.",
                                           "Model refresh: export -> Glue layers -> exports -> train -> evaluate -> publish model results to RDS -> register; model monitor export via Glue; EventBridge connection and write-back removed."]),
        ("Stage 11 - CI/CD with GitHub Actions", ["optimizer-ci builds the ECS image; deploy.yml registers optimizer task revisions + SSM pointer and uploads Glue scripts; glue.yml tests data/glue/; databricks.yml and DATABRICKS_CLIENT_ID removed. GitHub variables OPTIMIZER_TASK_FAMILY, OPTIMIZER_TASK_PARAM, GLUE_ASSETS_BUCKET, UPLOADS_BUCKET."]),
        ("Stage 12 - Front door and login", ["Unchanged: Route 53 / WBD DNS, ACM, regional WAF, ALB authenticate-oidc with Okta."]),
        ("Stage 13 - Logging and monitoring", ["Glue job failed / duration, Data Quality failed, Databricks export errors, optimizer RunTask failures, Fargate vCPU usage; optimization dashboard on ECS tasks; new data-pipeline dashboard; write-back alarm removed."]),
        ("Stage 14 - Backup and DR", ["Selection unchanged (uploads versioned, not in AWS Backup; glue-assets rebuilt from Git); RDS PITR + Multi-AZ failover test in staging."]),
        ("Stage 15 - Testing and Release 1 go-live", ["End-to-end refresh in dev (Databricks export -> Glue -> SageMaker -> RDS); optimizer start time and typical run < 2 min; 50 / 100 / 150 planners with the Fargate quota; uploads and future titles; DAST and pen test; parallel run and UAT; CAB; cutover."]),
        ("Stage 16 - Release 2 GenAI", ["Gateway unchanged; explanation tool on every run with token quotas per run; moves into Release 1 only with WBD approval."]),
        ("Stage 17 - Handover", ["Runbooks updated: model-refresh-failed (export, Glue, DQ, RDS export), optimization-run-failed (ECS task), scale-planning-season (+ Fargate quota, Glue workers), rotation (+ export SP, rds/etl), deploy / rollback (optimizer revision, Glue scripts); new glue-job-failed, databricks-export-failed; write-back-failed removed."]),
    ]
    for name, items in stages:
        h(name, 2)
        bullets(items)

    h("10. Questions for WBD (v4) and the proposed default")
    p("Each open point has a simpler industry-standard default; the last column says what WBD has to confirm. "
      "The per-environment inputs are in devops_4_client_question.xlsx.")
    table(["#", "Question", "Proposed default", "Confirm"],
          [(str(i), *row) for i, row in enumerate(DECISIONS, 1)])

    h("10a. Impact on the current code (v3 build)")
    bullets([
        "Remove: Databricks HTTP Task + write-back states, the EventBridge connection, databricks_refresh_job_id / databricks_writeback_job_id, "
        "the SageMaker optimization job + role + image pointer + mmm/sagemaker-optimizer, optimizer_instance_type, databricks.yml, "
        "DATABRICKS_CLIENT_ID, data/databricks/, runbook write-back-failed.",
        "Add: modules/glue (catalog, security configuration, connections, jobs, Data Quality, role), the Databricks export Lambda + secret, "
        "uploads and glue-assets buckets, optimizer ECS task definition + role + SSM pointer, glue endpoint + SG, rds/etl, glue.yml, "
        "ecs/<env>/optimizer.json, runbooks glue-job-failed and databricks-export-failed, data-pipeline dashboard.",
        "Change: databricks-access (write-only raw/databricks/), network (glue endpoint, SGs), ecr (mmm/optimizer), sagemaker (no optimization role), "
        "iam-oidc (deploy role), monitoring; optimization.tf (ecs:runTask.sync), data.tf (refresh + monitor states), main.tf, ecs.tf, outputs, "
        "variables, tfvars; optimizer-ci, deploy.yml; scripts (dry run, platform check, setup-github, db-bootstrap); data/README.md; docs and runbooks.",
        "Unchanged: bootstrap, KMS key set, RDS + Proxy, run queue + dispatcher, ECS cluster / ui / api / migrate, ALB + Okta, WAF, SageMaker training / "
        "evaluation / registry + governance, drift monitor core, GenAI gateway, log shipping, backup, app CI workflows (api, ui, training, publisher), "
        "terraform.yml, model-governance.yml, repo-checks.yml.",
        "Status: plan only (12 Nov 2026); implement after the user verifies the _4 documents.",
    ])

    h("11. Risks")
    table(["Risk", "Mitigation"], [
        ("Databricks export depends on another team's job, IP access list and service principal", "Clear contract (target URI, manifest), export-failed runbook and alarm, PrivateLink option, SP secret rotation"),
        ("Glue job cost and run time grow with 3+ years of history per BU", "Job bookmarks (incremental), per-BU partitions, worker sizing from data volumes, DPU-hours on the cost dashboard"),
        ("Bad source data reaches the models", "Glue Data Quality in Silver stops the refresh; DQ results on the data-pipeline dashboard"),
        ("Fargate quota or capacity limits optimization in peak season", "Quota >= max_concurrent_runs x task vCPU before the season; RunTask retries on capacity errors; queue holds the rest"),
        ("Two writers into RDS (Glue mmm_etl, publisher) besides the API", "Separate DB users with least privilege via RDS Proxy; tables owned by the backend's migrations; RLS per BU"),
        ("User uploads carry malware or another BU's data", "Presigned URLs scoped to the user's BU prefix and key; TLS-only; optional GuardDuty Malware Protection"),
        ("Explanation on every run sends data to external LLM providers", "GenAI off until written approval; Bedrock-hosted models as the alternative; guardrails on every call; the run never fails because of the LLM"),
    ])

    h("12. AWS resource list summary (details in aws_resource_list_4.xlsx)")
    table(["Layer", "Resources", "Dev", "Stage", "Prod", "New in v4", "Changed"], [
        (layer,
         sum(1 for r in ROWS if r[1] == layer),
         sum(1 for r in ROWS if r[1] == layer and "dev" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and "staging" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and "prod" in r[5]),
         sum(1 for r in ROWS if r[1] == layer and r[4] == "New"),
         sum(1 for r in ROWS if r[1] == layer and r[4] == "Changed"))
        for layer in dict.fromkeys(r[1] for r in ROWS)
    ] + [("Removed vs v3", len(REMOVED), "", "", "", "", "")])
    d.save(OUT / "wbd_mmm_ecs_final_4.docx")


build_xlsx()
if "--xlsx-only" not in sys.argv:
    build_docx()
print("full rows:", len(ROWS), "new detail:", len(V4_NEW), "changed detail:", len(V4_CHANGED), "removed:", len(REMOVED))

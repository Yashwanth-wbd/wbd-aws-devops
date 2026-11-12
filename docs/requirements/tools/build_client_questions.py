"""Builds docs/requirements/devops_4_client_question.xlsx - inputs only WBD can provide for requirement 4
(WBD_MMM_Architecture_4.pptx).

Full list for v4: the v1-v3 questions that v4 still needs (reworded where v4 changes them) plus the new v4 questions.
Questions v4 makes obsolete are on the 'removed_vs_v3' sheet. devops_3_client_question.xlsx (requirement 3) and
devops_2_client_question.xlsx (requirement 2) are kept for history; their generators are in git history.

Usage: uv run --no-project --with openpyxl python build_client_questions.py <docs/requirements path>
"""
import sys
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent

NEW, CHANGED, KEPT = "New in v4", "Changed by v4", "From v3"

# (v4 status, section, what the client provides, example / format (default in the code), where it goes, WBD owner)
INPUTS = [
    (KEPT, "1. AWS accounts and access", "AWS account IDs (dev, staging, prod)", "12 digits", "infra/bootstrap/*.tfvars, env terraform.tfvars", "Cloud Platform"),
    (KEPT, "1. AWS accounts and access", "Approved primary region and DR region (AWS Glue must be available there)", "us-east-1, us-west-2", "aws_region, allowed_regions, dr_region", "Cloud Platform"),
    (KEPT, "1. AWS accounts and access", "IAM Identity Center start URL", "https://d-xxxxxxxxxx.awsapps.com/start", "AWS CLI SSO profiles (docs/02)", "Identity"),
    (KEPT, "1. AWS accounts and access", "Permission sets and Okta groups for DevOps", "DevOps (dev, staging), ReadOnly (all), prod time-limited elevation", "Okta group membership", "Identity / Cloud Platform"),
    (KEPT, "1. AWS accounts and access", "One-time bootstrap: WBD runs it, or time-limited elevation", "Change ticket", "infra/bootstrap, first apply, GitHub OIDC provider", "Cloud Platform"),
    (KEPT, "1. AWS accounts and access", "Confirm the account baseline is on", "CloudTrail org trail (to EventBridge), GuardDuty, Security Hub, Config, SCPs", "Verified only", "Security"),
    (CHANGED, "1. AWS accounts and access", "Service quota increases approved (v4: Fargate vCPU and Glue replace the SageMaker Processing quota for optimization)", "SageMaker Training instances; Fargate On-Demand vCPU and Glue concurrent runs / DPUs (sections 7 and 10)", "AWS Service Quotas", "Cloud Platform"),
    (KEPT, "2. Network", "VPC CIDR per environment (no overlap with WBD)", "10.x.x.0/19", "vpc_cidr", "Network"),
    (KEPT, "2. Network", "Availability Zone IDs", "use1-az1, use1-az2 (+ a 3rd for staging/prod)", "availability_zone_ids", "Network"),
    (KEPT, "2. Network", "Transit Gateway ID and WBD routes (if connecting to WBD's network)", "tgw-..., 10.0.0.0/8", "transit_gateway_id, transit_gateway_routes", "Network"),
    (KEPT, "2. Network", "DNS forwarding domains and resolver IPs (if needed)", "wbd.internal -> IPs", "resolver_forward_domains, resolver_target_ips", "Network"),
    (CHANGED, "2. Network", "Internet egress: NAT allowed, or central firewall / proxy (v4: the Databricks export Lambda calls the workspace through NAT unless PrivateLink is used)", "yes / no", "enable_nat_gateway", "Network"),
    (KEPT, "2. Network", "Who may reach the app: internet or only WBD ranges", "CIDR list", "alb_ingress_cidrs", "Security / Network"),
    (KEPT, "2. Network", "Proxy CA certificate for the VDI and allow-listed URLs (GitHub, PyPI, npm, Terraform registry, LLM providers, Splunk)", ".pem file", "NODE_EXTRA_CA_CERTS / REQUESTS_CA_BUNDLE, firewall rules", "Network"),
    (KEPT, "3. Domain, certificate and sign-in", "App domain name per environment (also the only CORS origin of the uploads bucket)", "mmm-dev.wbd.com, mmm-stg.wbd.com, mmm.wbd.com", "app_domain_name", "DNS"),
    (KEPT, "3. Domain, certificate and sign-in", "DNS records created on WBD's side (we give dns_records_for_wbd)", "CNAME to the load balancer", "WBD DNS", "DNS"),
    (KEPT, "3. Domain, certificate and sign-in", "ACM certificate issued in the workload region", "arn:aws:acm:...:certificate/...", "alb_certificate_arn", "DNS / PKI"),
    (KEPT, "3. Domain, certificate and sign-in", "Okta OIDC web app per environment (we give okta_app_settings: sign-in redirect https://<app>/oauth2/idpresponse, sign-out redirect): issuer URL and client ID", "https://wbd.okta.com (or .../oauth2/<server-id>), 0oa...", "okta_issuer, okta_client_id", "Identity"),
    (KEPT, "3. Domain, certificate and sign-in", "Okta client secret of that app (entered in AWS by WBD or DevOps, never sent by email)", "{\"client_secret\": \"...\"}", "secret mmm/<env>/okta/alb-client, then okta_sign_in_enabled = true", "Identity"),
    (KEPT, "3. Domain, certificate and sign-in", "Okta group names for business unit and role, sent as a groups claim in the ID token; sign-out with client_id allowed", "mmm-bu-streaming, mmm-role-planner, claim groups", "Okta app, docs/04, docs/06", "Identity"),
    (KEPT, "3. Domain, certificate and sign-in", "Session length; MFA / step-up login for approvals", "12 hours", "session_hours", "Identity"),
    (KEPT, "4. GitHub and release approvals", "GitHub organization and repository (final home of the repo)", "wbd-org/wbd-mmm-devops", "github_org, github_repo (OIDC trust)", "GitHub admins"),
    (KEPT, "4. GitHub and release approvals", "Repo admin rights for DevOps (Environments, variables, branch protection)", "Admin role", "scripts/setup-github.ps1", "GitHub admins"),
    (CHANGED, "4. GitHub and release approvals", "Approvers: staging (EY), prod (WBD), model promotion; v4 adds approval of Glue script releases to staging / prod (glue.yml)", "GitHub users or team slugs", "GitHub Environments", "WBD / EY"),
    (KEPT, "4. GitHub and release approvals", "CODEOWNERS team names (incl. the data engineers for data/glue/)", "@wbd-org/mmm-devops", ".github/CODEOWNERS", "WBD / EY"),
    (KEPT, "4. GitHub and release approvals", "CAB change-ticket format for prod", "CHG1234567", "CHANGE_TICKET_PATTERN in deploy.yml", "CAB"),
    (KEPT, "4. GitHub and release approvals", "Approved security tools and licences (SAST, DAST, GitHub Advanced Security)", "Semgrep / CodeQL / ZAP", "repo-checks.yml", "Security"),
    (CHANGED, "5. Operations, security and cost", "Database size per environment: RDS PostgreSQL instance class, storage, Multi-AZ (v4: RDS also holds the Gold reference tables and model results)", "dev db.t4g.medium single-AZ, staging db.r6g.large Multi-AZ, prod db.r6g.xlarge Multi-AZ, 50 / 100 / 200 GiB", "rds_instance_class, rds_allocated_storage, rds_max_allocated_storage, rds_multi_az", "Architecture / Ops"),
    (CHANGED, "5. Operations, security and cost", "Optimization runs allowed at the same time and how long a request may wait in the queue (v4: bounded by the Fargate vCPU quota, section 7)", "5 / 20 / 50 runs; 30 minutes", "max_concurrent_runs, max_queue_wait_minutes", "Business / EY"),
    (KEPT, "5. Operations, security and cost", "Alert and budget email lists, paging tool", "mmm-oncall@wbd.com", "alert_emails, budget_alert_emails", "Ops"),
    (CHANGED, "5. Operations, security and cost", "Monthly budget per account (v4 adds Glue DPU-hours and Fargate optimizer tasks)", "USD", "monthly_budget_usd", "Finance"),
    (KEPT, "5. Operations, security and cost", "Splunk HEC endpoint, HEC token (entered in AWS by WBD), index, source type", "URL", "splunk_hec_endpoint; secret mmm/<env>/splunk/hec", "Splunk"),
    (KEPT, "5. Operations, security and cost", "Retention: logs, approved scenarios (Object Lock), training data", "e.g. 7 years", "log retention, approved_worm_retention_days, training_data_retention_days", "Legal / Audit"),
    (KEPT, "5. Operations, security and cost", "RPO / RTO sign-off; cross-region backup copy and prod vault lock approval", "yes / no", "enable_cross_region_copy, enable_vault_lock", "Ops / Security"),
    (KEPT, "5. Operations, security and cost", "Web firewall policy: rate limit, country allow-list", "2000, [\"US\"]", "waf_rate_limit, geo_allow_countries", "Security"),
    (KEPT, "5. Operations, security and cost", "Security incident contact, operations owner after handover, hypercare length", "Names", "runbooks, docs/13", "Security / Ops"),
    (CHANGED, "6. Data platform", "Databricks workspace URL and account ID (v4: used by the export Lambda)", "https://dbc-....cloud.databricks.com, UUID", "databricks_host, databricks_account_id", "Databricks"),
    (CHANGED, "6. Data platform", "PrivateLink to the Databricks workspace yes / no and service name (v4: for the export Lambda)", "com.amazonaws.vpce....", "enable_databricks_privatelink, databricks_privatelink_service_name", "Databricks / Network"),
    (KEPT, "6. Data platform", "Business unit names, refresh schedule and timezone", "streaming, theatrical, usnetworks; cron(...), America/New_York", "business_units, model_refresh_schedule, model_refresh_timezone", "Data"),
    (CHANGED, "6. Data platform", "Third-party vendors and their API keys (entered by WBD) - still needed now that source data arrives through the Databricks export?", "adstra, inscape / none", "third_party_vendors; secrets mmm/<env>/thirdparty/<vendor>", "Data owners"),
    (KEPT, "6. Data platform", "Model acceptance thresholds per business unit and the named model approver", "MAPE, R2, ...", "data/model-thresholds.yaml, <env>-model-promotion", "Data science"),
    (KEPT, "6. Data platform", "Model drift: threshold per business unit, check schedule, retrain automatically or alert only", "0.2; daily cron(0 7 * * ? *); alert only", "data/model-thresholds.yaml drift.threshold, model_monitor_schedule, auto_refresh_on_drift", "Data science"),
    (NEW, "7. Optimization on ECS", "Inference & optimization task size (vCPU / memory / disk) and maximum run time per run", "4 vCPU / 16 GiB / 50 GiB (prod 8 vCPU / 32 GiB); 60 minutes", "optimizer_cpu, optimizer_memory, optimizer_ephemeral_storage_gib, optimizer_max_runtime_seconds", "Data science"),
    (NEW, "7. Optimization on ECS", "Fargate On-Demand vCPU quota increase approved (runs at the same time x task vCPU + api / ui)", "dev >= 40, staging >= 120, prod >= 450 vCPU", "AWS Service Quotas (before the load test)", "Cloud Platform"),
    (NEW, "8. User uploads", "Accepted file types and maximum file size of the user input files", "xlsx / csv, 50 MB", "API (presigned PUT), uploads bucket", "Product / Security"),
    (NEW, "8. User uploads", "How long the uploaded input files are kept", "90 days", "uploads_retention_days", "Legal / Data owners"),
    (NEW, "8. User uploads", "Malware scanning of uploads required? (GuardDuty Malware Protection for S3 - not built yet)", "yes / no", "would add a switch on the uploads bucket", "Security"),
    (NEW, "8. User uploads", "'Upload future titles' file format and how it is used", "template xlsx; run type forecast", "API contract, data/README.md", "Product / Data science"),
    (NEW, "9. Databricks export", "Source catalog / schema / tables to export per business unit (3+ years of history), size and expected growth", "wbd_prod.mmm.<table>; GB per BU", "data/README.md, Glue sizing", "Databricks / Data owners"),
    (NEW, "9. Databricks export", "Export job ID per business unit and who owns the job; the job accepts business_unit, output_uri, purpose, request_id and writes Parquet to output_uri", "{\"streaming\": 123, ...}", "databricks_export_job_ids (SSM databricks/export_job_ids)", "Databricks / Data"),
    (NEW, "9. Databricks export", "Service principal for the export Lambda ('Can manage run' on the export jobs): client ID and OAuth secret (entered in AWS by WBD or DevOps, never by email)", "{\"client_id\": \"...\", \"client_secret\": \"...\"}", "secret mmm/<env>/databricks/export-sp", "Databricks"),
    (NEW, "9. Databricks export", "Unity Catalog external location on our landing prefix raw/databricks/ (we give the IAM role ARN; write-only)", "Registered by the Databricks admins", "terraform output data_platform (uc_role_arn)", "Databricks"),
    (NEW, "9. Databricks export", "Workspace IP access list allows our NAT IPs (export Lambda), or PrivateLink is used", "terraform output nat_public_ips", "Databricks workspace settings", "Databricks / Network"),
    (NEW, "10. Glue lakehouse", "AWS Glue version and worker size per environment", "Glue 5.0; G.1X x 2 / 5 / 10 workers; 120-minute timeout", "glue_version, glue_worker_type, glue_number_of_workers, glue_job_timeout_minutes", "Data / Architecture"),
    (NEW, "10. Glue lakehouse", "Glue concurrent job runs / DPU quota approved", "6 jobs x business units at the same time", "AWS Service Quotas", "Cloud Platform"),
    (NEW, "10. Glue lakehouse", "Is the Glue Data Catalog encryption (account-wide setting) already managed by WBD?", "no - this stack sets it", "manage_glue_catalog_encryption", "Cloud Platform / Security"),
    (NEW, "10. Glue lakehouse", "AWS Lake Formation required, or IAM only?", "IAM only", "would be added to modules/glue", "Security / Data"),
    (NEW, "10. Glue lakehouse", "Data-quality rules for the Silver layer, who owns them, behaviour on failure", "DQDL rules; stop the refresh", "data/glue/dq/silver.dqdl", "Data engineering"),
    (NEW, "10. Glue lakehouse", "Gold tables that must be exported to RDS for the app; approval of the ETL DB user mmm_etl", "<bu>_titles, <bu>_inventory_history", "Glue export-rds, backend migrations, secret mmm/<env>/rds/etl", "Data / Backend"),
    (NEW, "11. Model results", "Model predictions, lift and evaluation in RDS: for every registered version or only approved ones", "every registered version (tagged with the package ARN)", "results publisher model_results", "Data science / Backend"),
    (CHANGED, "12. GenAI", "Written approval for data to external LLM providers; approved providers (Anthropic via Bedrock?) - v4 calls the explanation tool on every run", "Approval document", "llm_providers", "Responsible AI / Legal"),
    (NEW, "12. GenAI", "Is GenAI part of Release 1 now that the explanation tool runs on every optimization, or Release 2?", "Release 2 (enable_genai = false)", "enable_genai, release plan", "Business / EY"),
    (KEPT, "12. GenAI", "Provider API keys (entered in AWS by WBD)", "{\"api_key\": \"...\"}", "secrets mmm/<env>/llm/<provider>", "Vendor contracts"),
    (CHANGED, "12. GenAI", "Token quotas per business unit (v4: sized for an explanation on every run) and guardrail policy (PII, denied topics, thresholds)", "tokens/day; 0.75", "genai_token_quotas, guardrail settings", "Responsible AI"),
    (NEW, "12. GenAI", "Token budget per run (explanation)", "~5,000 tokens per run", "genai_token_quotas", "Responsible AI"),
]

# (id, v4 status, question, default in the code)
DECISIONS = [
    ("Q1", NEW, "The Lambda next to Databricks on slide 1 is labelled 'Results publisher' - is it a separate export Lambda?", "Separate mmm-<env>-databricks-export Lambda; the results publisher stays the RDS writer"),
    ("Q2", NEW, "How does data leave Databricks: the export job pushes to our S3, or the Lambda pulls?", "Export job pushes to landing raw/databricks/ through a write-only Unity Catalog role; the Lambda starts and polls it"),
    ("Q3", NEW, "Glue orchestration: Glue workflows / triggers or Step Functions?", "Step Functions glue:startJobRun.sync per layer inside model-refresh"),
    ("Q4", NEW, "AWS Lake Formation on the Glue catalog", "Not used - IAM role, bucket policies and per-BU keys"),
    ("Q5", NEW, "Silver data-quality failure", "Stops the refresh and alerts (glue-data-quality-failed)"),
    ("Q6", NEW, "Glue export to RDS: DB user and path", "mmm_etl through RDS Proxy with an IAM token; tables from the backend migrations"),
    ("Q7", NEW, "Order of the last refresh steps (replaces the v3 write-back question)", "Register the model first, then write the results to RDS (rows carry the model package ARN)"),
    ("Q8", NEW, "Optimizer on ECS: one task per run or a worker service", "One Fargate task per run (Step Functions RunTask)"),
    ("Q9", CHANGED, "Runs at the same time with ECS; fairness between business units", "Unchanged 5 / 20 / 50, now bounded by the Fargate vCPU quota; order of arrival; per-user limits in the app"),
    ("Q10", NEW, "Forecast runs ('upload future titles'): separate flow?", "Same queue, state machine and optimizer image; run_type forecast; files in uploads/<bu>/runs/<run_id>/input/"),
    ("Q11", NEW, "Malware scanning of user uploads", "Not built; uploads only through the API's presigned URL, CORS limited to the app URL"),
    ("Q12", NEW, "Explanation tool on every run (GenAI)", "Stays behind enable_genai; the run succeeds without the explanation"),
    ("Q13", CHANGED, "Data leaving AWS to the LLM providers (now on every run)", "GenAI off until approved; Bedrock-hosted models as the alternative"),
    ("Q14", CHANGED, "Databricks IP access list must allow our calls (v4: the export Lambda's NAT IPs, not Step Functions)", "Allow-list terraform output nat_public_ips, or PrivateLink"),
    ("Q15", KEPT, "App reachable from the internet or only WBD ranges? Shield Advanced?", "Internet + web firewall + Okta sign-in; no Shield Advanced"),
    ("Q16", KEPT, "Okta: OIDC app at the load balancer (no Cognito), group names, sign-out", "One OIDC app per environment; mmm-bu-* / mmm-role-*; Okta logout with client_id"),
    ("Q17", KEPT, "Okta client secret is kept in the encrypted Terraform state (read from Secrets Manager)", "Accepted; state bucket restricted and KMS-encrypted"),
    ("Q18", KEPT, "Database: RDS PostgreSQL instance sizes, Multi-AZ, read replica", "Single-AZ dev, Multi-AZ staging / prod, no read replica"),
    ("Q19", KEPT, "Model drift above the threshold: alert or retrain automatically", "Alert only; daily check off until the first approved model"),
    ("Q20", KEPT, "Lakehouse backup size and cost (now written by Glue)", "Backed up"),
    ("Q21", KEPT, "Shared tooling account", "Not used (GitHub-hosted runners)"),
]

# (v3 question, why v4 no longer needs it)
REMOVED = [
    ("Service principal for model refresh: client ID (EventBridge connection)", "No Databricks HTTP Tasks any more; the export Lambda uses the export service principal (secret databricks/export-sp)"),
    ("Service principal for bundle deploy: client ID (GitHub variable DATABRICKS_CLIENT_ID)", "databricks.yml removed; Glue scripts ship with glue.yml"),
    ("Refresh job ID (databricks_refresh_job_id)", "Bronze / Silver / Gold run on AWS Glue; replaced by the export job ID per business unit"),
    ("Write-back job ID and target Gold tables (databricks_writeback_job_id)", "Model results are written to RDS by the results publisher (row 'Model predictions, lift and evaluation in RDS')"),
    ("Source data delivery method (S3 drop / SFTP / API)", "Slide 1: source data comes from the Databricks source catalog through the export job"),
    ("SageMaker Processing instance quota >= max_concurrent_runs", "Optimization runs on ECS Fargate; Fargate vCPU quota instead"),
    ("Decision Q6 (v3): one or two Databricks service principals", "One service principal (export) in v4"),
    ("Decision Q9 (v3): write-back of every registered version or only approved ones", "Replaced by v4 Q7 and the model-results input row"),
]

HEADER_FILL = PatternFill("solid", fgColor="1F4E78")
HEADER_FONT = Font(bold=True, color="FFFFFF")
INPUT_FILL = PatternFill("solid", fgColor="FFF2CC")
NEW_FILL = PatternFill("solid", fgColor="FCE4D6")
CHANGED_FILL = PatternFill("solid", fgColor="E2EFDA")
WRAP = Alignment(wrap_text=True, vertical="top")


def sheet(ws, title, headers, rows, widths, input_cols=(), status_col=None):
    ws.append([title])
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(headers)
    for c in ws[3]:
        c.fill, c.font, c.alignment = HEADER_FILL, HEADER_FONT, WRAP
    for r in rows:
        ws.append(list(r))
    for row in ws.iter_rows(min_row=4):
        status = row[status_col - 1].value if status_col else None
        for c in row:
            c.alignment = WRAP
            if c.column in input_cols:
                c.fill = INPUT_FILL
            elif status == NEW:
                c.fill = NEW_FILL
            elif status == CHANGED:
                c.fill = CHANGED_FILL
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A4"
    ws.auto_filter.ref = f"A3:{get_column_letter(len(headers))}{ws.max_row}"


wb = Workbook()
ws = wb.active
ws.title = "client_inputs"
sheet(
    ws,
    "WBD MMM requirement 4 - all inputs only WBD can provide (v3 inputs still needed + new v4 inputs; orange = new in v4, "
    "green = changed by v4; fill the yellow columns per environment)",
    ["#", "v4 status", "Section", "What the client provides", "Example / format (default in the code)", "Where it goes",
     "WBD owner", "Dev value", "Staging value", "Prod value", "Status", "Notes"],
    [(i, *r, "", "", "", "Open", "") for i, r in enumerate(INPUTS, 1)],
    [5, 14, 26, 52, 36, 40, 20, 22, 22, 22, 10, 30],
    input_cols=(8, 9, 10, 11, 12),
    status_col=2,
)
sheet(
    wb.create_sheet("decisions_to_confirm"),
    "Requirement 4 decisions - default built in the code until WBD confirms (orange = new in v4, green = changed by v4)",
    ["#", "v4 status", "Question", "Default built", "WBD answer", "Status"],
    [(*d, "", "Open") for d in DECISIONS],
    [6, 14, 60, 60, 40, 10],
    input_cols=(5, 6),
    status_col=2,
)
sheet(
    wb.create_sheet("removed_vs_v3"),
    "v3 questions that requirement 4 no longer needs (do not send)",
    ["#", "v3 question", "Why not needed in v4"],
    [(i, *r) for i, r in enumerate(REMOVED, 1)],
    [5, 60, 80],
)
wb.save(OUT / "devops_4_client_question.xlsx")
counts = {s: sum(1 for r in INPUTS if r[0] == s) for s in (NEW, CHANGED, KEPT)}
print("inputs:", len(INPUTS), counts, "decisions:", len(DECISIONS), "removed:", len(REMOVED))

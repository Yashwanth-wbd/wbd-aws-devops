"""Builds docs/requirements/devops_2_client_question.xlsx - inputs only WBD can provide (requirement 2).

Usage: uv run --no-project --with openpyxl python build_client_questions.py <docs/requirements path>
"""
import sys
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent

# (section, what the client provides, example / format, where it goes, WBD owner)
INPUTS = [
    ("1. AWS accounts and access", "AWS account IDs (dev, staging, prod)", "12 digits", "infra/bootstrap/*.tfvars, env terraform.tfvars", "Cloud Platform"),
    ("1. AWS accounts and access", "Approved primary region and DR region", "us-east-1, us-west-2", "aws_region, allowed_regions, dr_region", "Cloud Platform"),
    ("1. AWS accounts and access", "IAM Identity Center start URL", "https://d-xxxxxxxxxx.awsapps.com/start", "AWS CLI SSO profiles (docs/02)", "Identity"),
    ("1. AWS accounts and access", "Permission sets and Okta groups for DevOps", "DevOps (dev, staging), ReadOnly (all), prod time-limited elevation", "Okta group membership", "Identity / Cloud Platform"),
    ("1. AWS accounts and access", "One-time bootstrap: WBD runs it, or time-limited elevation", "Change ticket", "infra/bootstrap, first apply, GitHub OIDC provider", "Cloud Platform"),
    ("1. AWS accounts and access", "Confirm the account baseline is on", "CloudTrail org trail (to EventBridge), GuardDuty, Security Hub, Config, SCPs", "Verified only", "Security"),
    ("1. AWS accounts and access", "Service quota increases approved", "SageMaker Processing / Training instances, Fargate vCPU", "AWS Service Quotas", "Cloud Platform"),
    ("2. Network", "VPC CIDR per environment (no overlap with WBD)", "10.x.x.0/19", "vpc_cidr", "Network"),
    ("2. Network", "Availability Zone IDs", "use1-az1, use1-az2 (+ a 3rd for staging/prod)", "availability_zone_ids", "Network"),
    ("2. Network", "Transit Gateway ID and WBD routes (if connecting to WBD's network)", "tgw-..., 10.0.0.0/8", "transit_gateway_id, transit_gateway_routes", "Network"),
    ("2. Network", "DNS forwarding domains and resolver IPs (if needed)", "wbd.internal -> IPs", "resolver_forward_domains, resolver_target_ips", "Network"),
    ("2. Network", "Internet egress: NAT allowed, or central firewall / proxy", "yes / no", "enable_nat_gateway", "Network"),
    ("2. Network", "Who may reach the app: internet or only WBD ranges", "CIDR list", "alb_ingress_cidrs", "Security / Network"),
    ("2. Network", "Proxy CA certificate for the VDI and allow-listed URLs (GitHub, PyPI, npm, Terraform registry, LLM providers, Splunk)", ".pem file", "NODE_EXTRA_CA_CERTS / REQUESTS_CA_BUNDLE, firewall rules", "Network"),
    ("3. Domain, certificate and sign-in", "App domain name per environment", "mmm-dev.wbd.com, mmm-stg.wbd.com, mmm.wbd.com", "app_domain_name", "DNS"),
    ("3. Domain, certificate and sign-in", "DNS records created on WBD's side (we give dns_records_for_wbd)", "CNAME to the load balancer", "WBD DNS", "DNS"),
    ("3. Domain, certificate and sign-in", "ACM certificate issued in the workload region", "arn:aws:acm:...:certificate/...", "alb_certificate_arn", "DNS / PKI"),
    ("3. Domain, certificate and sign-in", "Okta SAML app per environment (we give okta_app_settings) and its metadata URL", "https://wbd.okta.com/app/.../sso/saml/metadata", "okta_saml_metadata_url", "Identity"),
    ("3. Domain, certificate and sign-in", "Okta group names for business unit and role, and the group attribute name", "mmm-bu-streaming, mmm-role-planner, attribute groups", "Okta app, docs/04, docs/06", "Identity"),
    ("3. Domain, certificate and sign-in", "Session length; MFA / step-up login for approvals", "12 hours", "session_hours", "Identity"),
    ("4. GitHub and release approvals", "GitHub organization and repository (final home of the repo)", "wbd-org/wbd-mmm-devops", "github_org, github_repo (OIDC trust)", "GitHub admins"),
    ("4. GitHub and release approvals", "Repo admin rights for DevOps (Environments, variables, branch protection)", "Admin role", "scripts/setup-github.ps1", "GitHub admins"),
    ("4. GitHub and release approvals", "Approvers: staging (EY), prod (WBD), model promotion", "GitHub users or team slugs", "GitHub Environments", "WBD / EY"),
    ("4. GitHub and release approvals", "CODEOWNERS team names", "@wbd-org/mmm-devops", ".github/CODEOWNERS", "WBD / EY"),
    ("4. GitHub and release approvals", "CAB change-ticket format for prod", "CHG1234567", "CHANGE_TICKET_PATTERN in deploy.yml", "CAB"),
    ("4. GitHub and release approvals", "Approved security tools and licences (SAST, DAST, GitHub Advanced Security)", "Semgrep / CodeQL / ZAP", "repo-checks.yml", "Security"),
    ("5. Operations, security and cost", "Alert and budget email lists, paging tool", "mmm-oncall@wbd.com", "alert_emails, budget_alert_emails", "Ops"),
    ("5. Operations, security and cost", "Monthly budget per account", "USD", "monthly_budget_usd", "Finance"),
    ("5. Operations, security and cost", "Splunk HEC endpoint, HEC token (entered in AWS by WBD), index, source type", "URL", "splunk_hec_endpoint; secret mmm/<env>/splunk/hec", "Splunk"),
    ("5. Operations, security and cost", "Retention: logs, approved scenarios (Object Lock), training data", "e.g. 7 years", "log retention, approved_worm_retention_days, training_data_retention_days", "Legal / Audit"),
    ("5. Operations, security and cost", "RPO / RTO sign-off; cross-region backup copy and prod vault lock approval", "yes / no", "enable_cross_region_copy, enable_vault_lock", "Ops / Security"),
    ("5. Operations, security and cost", "Web firewall policy: rate limit, country allow-list", "2000, [\"US\"]", "waf_rate_limit, geo_allow_countries", "Security"),
    ("5. Operations, security and cost", "Security incident contact, operations owner after handover, hypercare length", "Names", "runbooks, docs/13", "Security / Ops"),
    ("6. Data platform", "Databricks workspace URL and account ID", "https://dbc-....cloud.databricks.com, UUID", "databricks_host, databricks_account_id", "Databricks"),
    ("6. Data platform", "Service principal for model refresh: client ID (WBD enters the OAuth secret in AWS)", "UUID", "databricks_sp_client_id, EventBridge connection", "Databricks"),
    ("6. Data platform", "Service principal for bundle deploy: client ID", "UUID", "GitHub variable DATABRICKS_CLIENT_ID", "Databricks"),
    ("6. Data platform", "Refresh job ID (after the data team creates the job)", "number", "databricks_refresh_job_id", "Data / EY"),
    ("6. Data platform", "Workspace IP access list allows AWS calls; PrivateLink yes / no and service name", "com.amazonaws.vpce....", "enable_databricks_privatelink, databricks_privatelink_service_name", "Databricks / Network"),
    ("6. Data platform", "Business unit names, refresh schedule and timezone", "streaming, theatrical, usnetworks; cron(...), America/New_York", "business_units, model_refresh_schedule, model_refresh_timezone", "Data"),
    ("6. Data platform", "Source data delivery method; third-party vendors and their API keys (entered by WBD)", "S3 drop / SFTP / API; adstra, inscape", "third_party_vendors; secrets mmm/<env>/thirdparty/<vendor>", "Data owners"),
    ("6. Data platform", "Model acceptance thresholds per business unit and the named model approver", "MAPE, R2, ...", "data/model-thresholds.yaml, <env>-model-promotion", "Data science"),
    ("7. Release 2 GenAI", "Written approval for data to external LLM providers; approved providers (Anthropic via Bedrock?)", "Approval document", "llm_providers", "Responsible AI / Legal"),
    ("7. Release 2 GenAI", "Provider API keys (entered in AWS by WBD)", "{\"api_key\": \"...\"}", "secrets mmm/<env>/llm/<provider>", "Vendor contracts"),
    ("7. Release 2 GenAI", "Token quotas per business unit; guardrail policy (PII, denied topics, thresholds)", "tokens/day; 0.75", "genai_token_quotas, guardrail settings", "Responsible AI"),
]

# (id, question, default in the code)
DECISIONS = [
    ("Q1", "App reachable from the internet or only WBD ranges? Shield Advanced?", "Internet + web firewall + Cognito; no Shield Advanced"),
    ("Q2", "Throttling for 50-150 planners without a queue", "Step Functions retries + app-side limit per user"),
    ("Q3", "Data leaving AWS to the LLM providers", "GenAI off until approved"),
    ("Q4", "Databricks IP access list must allow Step Functions calls", "To confirm"),
    ("Q5", "Okta group names", "mmm-bu-* / mmm-role-*"),
    ("Q6", "One or two Databricks service principals (refresh and deploy)", "Two"),
    ("-", "Lakehouse backup size and cost", "Backed up"),
    ("-", "Shared tooling account", "Not used (GitHub-hosted runners)"),
]

HEADER_FILL = PatternFill("solid", fgColor="1F4E78")
HEADER_FONT = Font(bold=True, color="FFFFFF")
INPUT_FILL = PatternFill("solid", fgColor="FFF2CC")
WRAP = Alignment(wrap_text=True, vertical="top")


def sheet(ws, title, headers, rows, widths, input_cols=()):
    ws.append([title])
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([])
    ws.append(headers)
    for c in ws[3]:
        c.fill, c.font, c.alignment = HEADER_FILL, HEADER_FONT, WRAP
    for r in rows:
        ws.append(list(r))
    for row in ws.iter_rows(min_row=4):
        for c in row:
            c.alignment = WRAP
            if c.column in input_cols:
                c.fill = INPUT_FILL
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A4"
    ws.auto_filter.ref = f"A3:{get_column_letter(len(headers))}{ws.max_row}"


wb = Workbook()
ws = wb.active
ws.title = "client_inputs"
sheet(
    ws,
    "WBD MMM requirement 2 - inputs only WBD can provide (fill the yellow columns per environment)",
    ["#", "Section", "What the client provides", "Example / format", "Where it goes", "WBD owner",
     "Dev value", "Staging value", "Prod value", "Status", "Notes"],
    [(i, *r, "", "", "", "Open", "") for i, r in enumerate(INPUTS, 1)],
    [5, 26, 48, 34, 38, 18, 22, 22, 22, 10, 30],
    input_cols=(7, 8, 9, 10, 11),
)
sheet(
    wb.create_sheet("decisions_to_confirm"),
    "Open decisions - default implemented until WBD confirms",
    ["#", "Question", "Default in the code", "WBD answer", "Status"],
    [(*d, "", "Open") for d in DECISIONS],
    [6, 60, 48, 40, 10],
    input_cols=(4, 5),
)
wb.save(OUT / "devops_2_client_question.xlsx")
print("inputs:", len(INPUTS), "decisions:", len(DECISIONS))

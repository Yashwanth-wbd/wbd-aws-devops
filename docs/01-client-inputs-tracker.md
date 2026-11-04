# 01 – Client inputs tracker (placeholder values)

The client has not shared real values yet, so the code uses the placeholders below. Every
placeholder in code has a `# add actual value` comment on the line above it. When WBD
supplies a value, update it everywhere it appears, set its status to **Received**, and run
`terraform plan` for the affected environment.

```powershell
# list every remaining placeholder
git grep -n -A1 "add actual value"
```

## AWS accounts and region

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| Dev account ID | `111111111111` | `infra/bootstrap/dev.tfvars`, `infra/environments/dev/terraform.tfvars` | WBD Cloud Platform | Open |
| Staging account ID | `222222222222` | `infra/bootstrap/staging.tfvars`, `infra/environments/staging/terraform.tfvars` | WBD Cloud Platform | Open |
| Prod account ID | `333333333333` | `infra/bootstrap/prod.tfvars`, `infra/environments/prod/terraform.tfvars` | WBD Cloud Platform | Open |
| Approved primary region | `us-east-1` | all `provider.tf` / tfvars | WBD Cloud Platform | Open |
| DR region (cross-region copy) | `us-west-2` | prod tfvars (backup, replication) | WBD Cloud Platform | Open |
| IAM Identity Center start URL | `https://d-0000000000.awsapps.com/start` | `docs/02-aws-access-sso-cli.md` | WBD Identity | Open |
| Permission set names | `ReadOnly`, `Developer`, `DevOps`, `SecurityAudit`, `BreakGlass` | AWS CLI profiles | WBD Identity | Open |
| Account baseline owned by WBD? (CloudTrail, GuardDuty, Security Hub, Config, SCPs) | yes – only verified, not created | not in Terraform | WBD Security | Decided (WBD to confirm it is enabled) |
| DynamoDB lock table required? | no – S3 lock file (`use_lockfile`) | `infra/bootstrap/*.tfvars` | WBD Cloud Platform | Decided (switch available) |

## Network

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| Dev VPC CIDR | `10.40.0.0/19` | dev tfvars | WBD Network | Open |
| Availability Zone IDs (dev 2, staging/prod 3) | dev `use1-az1`, `use1-az2`; staging/prod add `use1-az4` | env tfvars `availability_zone_ids` | WBD Network | Open – list with `aws ec2 describe-availability-zones --query "AvailabilityZones[].[ZoneName,ZoneId]"` |
| Staging VPC CIDR | `10.40.32.0/19` | staging tfvars | WBD Network | Open |
| Prod VPC CIDR | `10.40.64.0/19` | prod tfvars | WBD Network | Open |
| Transit Gateway ID + WBD CIDRs to route | `tgw-00000000000000000`, `10.0.0.0/8` (`enable_transit_gateway = false`) | env tfvars | WBD Network | Open |
| Central egress firewall instead of NAT? | assumed no (`enable_nat_gateway = true`) | env tfvars | WBD Network | Open |
| Resolver forward domains + target IPs | `wbd.internal` → `10.0.0.2`, `10.0.0.3` (`enable_resolver_forwarding = false`) | env tfvars | WBD Network | Open |
| Existing VPC to reuse (if any) | none – new VPC created | network module | WBD Network | Open |
| CloudFront origin-facing prefix list ID | looked up by name in the network module | ALB security group | AWS | Decided – no input needed |

## GitHub and CI/CD

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| GitHub organisation | `wbd-org` | OIDC trust policies | WBD GitHub admins | Open |
| Repository name | `wbd-mmm-platform` | OIDC trust policies | WBD GitHub admins | Open |
| GitHub Actions approved instead of Jenkins | assumed yes | `.github/workflows/` | WBD | Open |
| Staging approver(s) | `ey-delivery-lead` | GitHub Environment `staging` | EY | Open |
| Prod approver(s) + CAB contact | `wbd-release-approver` | GitHub Environment `prod` | WBD | Open |
| CODEOWNERS teams | deferred | `.github/CODEOWNERS` | WBD | Deferred |
| SAST tool licence (CodeQL / Semgrep / SonarQube) | Semgrep OSS (`p/default`, `p/python`, `p/react`) | `repo-checks.yml` | WBD | Open |
| GitHub team slugs for approvers | `ey-delivery-leads`, `wbd-release-approvers` | `scripts/setup-github.ps1` | EY / WBD | Open |
| Change-ticket format for prod (CAB) | `CHG` + 7 digits in the annotated tag message | `deploy.yml` (`CHANGE_TICKET_PATTERN`) | WBD CAB | Open |
| Pin actions to commit SHAs? | major tags (`@v5`), Dependabot | `.github/workflows/` | WBD Security | Open |
| GitHub Advanced Security (secret scanning push protection, CodeQL) | not assumed | repo settings | WBD | Open |
| App start / migration commands, health path, frontend build folder | `uvicorn app.main:app`, `python -m worker`, `alembic upgrade head`, `/api/health`, `dist/` | `ecs/<env>/*.json`, `frontend-ci.yml` | EY dev teams | Open |
| Test coverage gate | 80 % | `_python-service-ci.yml` (`coverage_min`) | EY / WBD | Open |
| Smoke URL before WBD DNS exists | CloudFront domain via `SMOKE_BASE_URL` | `deploy.yml` | EY | Open |

## Security, logging, operations

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| CostCenter tag | `CC-000000` | all tfvars | WBD Finance | Open |
| Monthly budget per account (USD) | dev `3000`, staging `6000`, prod `15000` | budgets module | WBD Finance | Open |
| Alert email (on-call / DevOps list) | `alert_emails = ["mmm-devops-alerts@example.wbd.com"]` | SNS topic `mmm-<env>-alerts` | WBD Ops | Open (Teams/Slack via AWS Chatbot can be added later) |
| Splunk HEC endpoint (reachable from Firehose IP ranges, CA-signed cert) | `splunk_hec_endpoint`, `enable_splunk_shipping = false` | log-shipping | WBD Splunk | Open |
| Splunk index and source type of the HEC token (indexer acknowledgement on) | – | Splunk side | WBD Splunk | Open |
| Ship VPC flow logs to Splunk? (licence volume) | `ship_vpc_flow_logs = false` | log-shipping | WBD Security / Splunk | Open |
| Existing account-level CloudWatch Logs data protection policy? | `enable_log_data_protection = true` | monitoring | WBD Cloud | Open |
| Break-glass permission set name (prod) and CloudTrail organization trail delivering to EventBridge | `breakglass_permission_set = "BreakGlass"` (module default) | monitoring rule `mmm-prd-breakglass-used` | WBD Identity / Security | Open (Step 15) |
| Severity levels, response times, on-call tool (paging) | proposal in `docs/runbooks/README.md` | runbooks, SNS subscriptions | WBD Ops | Open (Step 15) |
| WBD security incident contact / escalation path | – | `docs/runbooks/security-incident.md` | WBD Security | Open (Step 15) |
| Operations owner after handover, RACI, hypercare length | proposal in `docs/13` (4 weeks hypercare) | `docs/13-operations-and-handover.md` | WBD Ops / EY delivery lead | Open (Step 15) |
| Splunk HEC token | none in Git – stored in Secrets Manager | `mmm/<env>/splunk/hec` | WBD Splunk | Open |
| Object Lock retention for approved scenarios | `2555` days (7 years), GOVERNANCE in dev/staging, COMPLIANCE in prod | S3 module | WBD Legal / Audit | Open |
| RDS instance class + storage per env | dev `db.t4g.medium` 50 GB; staging `db.r6g.large` 100 GB; prod `db.r6g.xlarge` 200 GB (autoscale to 1000) | env tfvars `rds_*` | WBD / EY sizing | Open |
| ElastiCache node type per env | dev `cache.t4g.small`; staging and prod `cache.r6g.large` | env tfvars `redis_node_type` | WBD / EY sizing | Open |
| ECS task counts per env (min–max) | api 1–2 / 2–4 / 3–10, what-if 1–2 / 1–4 / 2–6, optimizer 0–3 / 0–5 / 0–10 | `ecs.tf` `local.scaling` | EY load test / WBD | Open |
| Log retention staging / prod | 90 / 365 days (CloudWatch), flow logs 90 / 365 | env tfvars | WBD Security / Audit | Open |
| Platform-check task in prod | `enable_platform_check_task = true` for go-live, then `false` | prod tfvars | EY | Open |
| Valkey acceptable instead of Redis OSS? | assumed yes (Valkey 8.0) | elasticache module `engine` | WBD Architecture | Open |
| RPO / RTO sign-off (per failure type) | proposal in `docs/08` section 1 (DB RPO ≤ 5 min, env rebuild RTO 4 h, region RTO 8 h) | backup module, docs/08 | WBD | Open |
| Cross-region backup copy approved? | prod only, `enable_cross_region_copy = false` until approved | backup module | WBD | Open |
| Vault lock (COMPLIANCE, irreversible) approved + retention (min 7 / max 400 days, monthly 365) | prod only, `enable_vault_lock = false` | backup module | WBD Security | Open |
| S3 cross-region replication of results / approved-worm (RPO minutes instead of 24 h) | not built: the DR copy of these buckets is the AWS Backup cross-region copy (daily, RPO 24 h). S3 replication only if WBD needs RPO in minutes | backup module (`enable_cross_region_copy`) | WBD | Proposed (Step 12) |

## Front door and Okta

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| App domain names (Step 8) + CNAMEs from `terraform output dns_records_for_wbd` | `mmm-dev.`, `mmm-stg.`, `mmm.example.wbd.com` (origins `origin-mmm-dev.`, `origin-mmm-stg.`, `origin-mmm.`) | env tfvars `cloudfront_aliases`, `alb_origin_domain_name` | WBD DNS | Open (Route 53 later) |
| CloudFront certificate (Step 8): ACM in **us-east-1** covering every alias | `cloudfront_certificate_arn` | edge module | WBD DNS / PKI | Open |
| ALB origin certificate (Step 7): ACM cert in `aws_region` for the origin name, e.g. `origin-mmm-dev.<wbd-domain>`, and a CNAME from that name to `alb_dns_name` | `alb_certificate_arn` in tfvars | alb module | WBD DNS / PKI | Open |
| Egress to PyPI through NAT (one-time DB bootstrap) or a WBD package mirror | – | `scripts/db-bootstrap.py` | WBD Network | Open |
| Okta org URL | `https://wbd.okta.com` | SSM `/mmm/<env>/okta/issuer` | WBD Identity | Open |
| Okta authorization server ID | `aus0000000000000000` | SSM `/mmm/<env>/okta/issuer` | WBD Identity | Open |
| Okta SPA client ID per environment | dev `0oa00000000000000000`, staging `…0001`, prod `…0002` | SSM `/mmm/<env>/okta/client_id` | WBD Identity | Open |
| Okta API audience (one per environment) | `api://mmm-dev`, `api://mmm-stg`, `api://mmm-prd` | SSM `/mmm/<env>/okta/audience` | WBD Identity | Open |
| Okta group names → BU + role | see `docs/04-okta-mfa-app-login.md` | Okta claims | WBD Identity | Open |
| Geo restriction for the app (Step 8) | `geo_allow_countries = []` (none) | edge module | WBD Security | Open |
| HSTS preload for the WBD domain (Step 8) | not set (2-year HSTS with subdomains only) | edge module | WBD domain owners | Open |
| Internet-facing or internal-only app? | assumed internet-facing behind CloudFront + WAF + Okta | edge module | WBD Security | Open |

## Data and AI

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| Databricks workspace host | `https://dbc-00000000-0000.cloud.databricks.com` | databricks-access module | WBD Databricks | Open |
| Databricks account ID | `00000000-0000-0000-0000-000000000000` | Unity Catalog IAM role trust | WBD Databricks | Open |
| Databricks PrivateLink service name | `com.amazonaws.vpce.us-east-1.vpce-svc-00000000000000000` | databricks-access module | WBD Databricks | Open |
| Databricks SQL warehouse HTTP path | `/sql/1.0/warehouses/0000000000000000` | worker task definitions | WBD Databricks | Open |
| Third-party vendors needing API keys | `adstra`, `inscape` | env tfvars `third_party_vendors` | WBD Data owners | Open |
| Databricks service-principal token | none in Git – Secrets Manager | `mmm/<env>/databricks/sp` | WBD Databricks | Open |
| Source feed delivery method (S3 / SFTP / API) | S3 drop to landing bucket | data-trigger module | WBD Data owners | Open |
| Orchestration: MWAA or Databricks Workflows | MWAA + EventBridge + Lambda behind `enable_data_platform` | Step 13 | User / WBD | Decided |
| Approved LLM model ID(s) (Release 2) | `genai_approved_model_ids = ["anthropic.claude-3-5-sonnet-20240620-v1:0"]` | bedrock module, gateway task role | WBD Responsible AI | Open |
| Token capacity / per-BU quotas | `1000000` tokens/day per BU | SSM quotas | WBD | Open |
| Guardrail thresholds (prompt attack, PII, grounding, relevance) | prompt attack `HIGH`, content `MEDIUM`, PII anonymize email/phone/name/address, block SSN/card/bank/keys/passwords, `genai_grounding_threshold = 0.75`, `genai_relevance_threshold = 0.75` | Bedrock Guardrails (Step 14) | WBD Responsible AI | Open |
| Bedrock invocation logging already configured in the accounts? | assumed no: `enable_bedrock_invocation_logging = true` | bedrock module (account + region singleton) | WBD Cloud Platform | Open |
| Monthly Bedrock budget | `genai_monthly_budget_usd` dev `200`, staging `500`, prod `2000` | bedrock module budget | WBD | Open |
| Cost Explorer service names of the approved models | `["Amazon Bedrock", "Claude 3.5 Sonnet (Amazon Bedrock Edition)"]` | `genai_budget_service_names` | WBD Finance | Open (check Cost Explorer after the first calls) |
| Bedrock model access / EULA per account | manual, Bedrock console (once per account) | Step 14 | WBD Cloud Platform | Open |
| Approved GenAI gateway base image | `python:3.12-slim` | `apps/genai-gateway/Dockerfile` | WBD Security | Open |
| Release 1 gate sign-offs (G1–G5) | – | `docs/11-release-1-readiness.md` | EY delivery lead / WBD | Open |
| Model-promotion approver | `wbd-model-approver` | GitHub Environment `<env>-model-promotion` | WBD | Open |
| Enable the data platform per environment | `enable_data_platform = false` | env tfvars (Step 13) | User / WBD Data | Open |
| Business unit names (S3 prefixes, keys, models) | `usnetworks`, `streaming`, `theatrical` | env tfvars `business_units` | WBD Data owners | Open |
| Unity Catalog storage-credential External ID | = `databricks_account_id` | Unity Catalog role trust (docs/10 §4) | WBD Databricks | Open |
| Unity Catalog catalog per environment | `mmm_dev`, `mmm_stg`, `mmm_prd` | env tfvars `databricks_catalog` (null = default) | WBD Databricks | Open |
| GitHub OIDC service principal for model evaluation | `00000000-0000-0000-0000-00000000e001` (dev), `…e002`, `…e003` | env tfvars `databricks_eval_client_id` | WBD Databricks | Open |
| GitHub OIDC service principal for model promotion | `00000000-0000-0000-0000-00000000a001` (dev), `…a002`, `…a003` | env tfvars `databricks_promote_client_id` | WBD Databricks | Open |
| Databricks PrivateLink in use? | `enable_databricks_privatelink = false` | env tfvars | WBD Databricks / Network | Open |
| Airflow → Databricks connection (SP OAuth secret) | none in Git – Secrets Manager | `mmm/<env>/airflow/connections/databricks_default` | WBD Databricks | Open |
| MWAA size per environment | dev/stg `mw1.small` 1–2 / 1–4 workers, prod `mw1.medium` 2–10 | `data.tf` `mwaa_sizing` | EY / WBD Data | Open |
| Model acceptance thresholds per business unit | MAPE ≤ 0.15/0.20, R² ≥ 0.80/0.75, R-hat ≤ 1.05, 0 negative channels | `data/model-thresholds.yaml` | WBD Data science / EY | Open |
| Databricks job names | `mmm-<env>-transform`, `-data-quality`, `-retrain` | `data/dags/mmm_ingest.py` | WBD Data team | Open |

# 01 – Client inputs tracker (placeholder values)

The client has not shared real values yet, so the code uses the placeholders below. Every
placeholder in code has a `# add actual value` comment on the line above it. When WBD
supplies a value, update it everywhere it appears, set its status to **Received**, and run
`terraform plan` for the affected environment.

The client-facing version of this list (only what WBD must provide, with dev / staging / prod
columns to fill) is `docs/requirements/devops_3_client_question.xlsx` (requirement 3: Okta OIDC, RDS
sizing, run limits, write-back, drift; the `_2` workbook is kept for history).

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
| ALB ingress CIDRs (who may reach HTTPS on the public ALB) | `["0.0.0.0/0"]` | env tfvars `alb_ingress_cidrs`, ALB security group | WBD Security / Network | Open – tighten to WBD egress ranges if required |

## GitHub and CI/CD

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| GitHub organisation | `Yashwanth-wbd` | OIDC trust policies | WBD GitHub admins | Open |
| Repository name | `wbd-aws-devops` | OIDC trust policies | WBD GitHub admins | Open |
| GitHub Actions approved instead of Jenkins | assumed yes | `.github/workflows/` | WBD | Open |
| Staging approver(s) | `ey-delivery-lead` | GitHub Environment `staging` | EY | Open |
| Prod approver(s) + CAB contact | `wbd-release-approver` | GitHub Environment `prod` | WBD | Open |
| CODEOWNERS teams | deferred | `.github/CODEOWNERS` | WBD | Deferred |
| SAST tool licence (CodeQL / Semgrep / SonarQube) | Semgrep OSS (`p/default`, `p/python`, `p/react`) | `repo-checks.yml` | WBD | Open |
| GitHub team slugs for approvers | `ey-delivery-leads`, `wbd-release-approvers` | `scripts/setup-github.ps1` | EY / WBD | Open |
| Change-ticket format for prod (CAB) | `CHG` + 7 digits in the annotated tag message | `deploy.yml` (`CHANGE_TICKET_PATTERN`) | WBD CAB | Open |
| Pin actions to commit SHAs? | pinned (`@<sha> # vX.Y.Z`), Dependabot updates them | `.github/workflows/` | WBD Security | Decided |
| GitHub Advanced Security (secret scanning push protection, CodeQL) | not assumed | repo settings | WBD | Open |
| App start / migration commands, health paths | API: `uvicorn app.main:app`, migrate: `alembic upgrade head`, `/api/health`, UI: `/healthz` | `ecs/<env>/{api,ui,migrate}.json`, `api-ci.yml`, `ui-ci.yml` | EY dev teams | Open |
| Test coverage gate | 80 % | `_python-service-ci.yml` (`coverage_min`) | EY / WBD | Open |
| Smoke URL before WBD DNS exists | `APP_URL` from Terraform (`https://<app_domain_name>`) or override `SMOKE_BASE_URL` | `deploy.yml`, `scripts/smoke.sh` | EY | Open – ALB DNS name works until DNS is cut over |

## Security, logging, operations

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
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
| RDS PostgreSQL instance class, storage and Multi-AZ per env | dev `db.t4g.medium` 50–200 GiB Single-AZ; staging `db.r6g.large` 100–500 GiB Multi-AZ; prod `db.r6g.xlarge` 200–1000 GiB Multi-AZ | env tfvars `rds_instance_class`, `rds_allocated_storage`, `rds_max_allocated_storage`, `rds_multi_az` | WBD / EY sizing | Open |
| Concurrent optimization runs (soft limit) and maximum queue wait | `max_concurrent_runs` 5 / 20 / 50; `max_queue_wait_minutes = 30` | env tfvars, SSM `/mmm/<env>/optimization/max_concurrent_runs` | WBD planners / EY | Open |
| ECS task counts per env (min–max, CPU autoscaling) | api 1–2 / 2–4 / 3–10; ui 1–2 / 2–3 / 2–6 | `ecs.tf` `local.ecs_sizing` | EY load test / WBD | Open |
| Log retention staging / prod | 90 / 365 days (CloudWatch), flow logs 90 / 365 | env tfvars | WBD Security / Audit | Open |
| Platform-check task in prod | `enable_platform_check_task = true` for go-live, then `false` | prod tfvars | EY | Open |
| RPO / RTO sign-off (per failure type) | proposal in `docs/08` section 1 (DB RPO ≤ 5 min, env rebuild RTO 4 h, region RTO 8 h) | backup module, docs/08 | WBD | Open |
| Cross-region backup copy approved? | prod only, `enable_cross_region_copy = false` until approved | backup module | WBD | Open |
| Vault lock (COMPLIANCE, irreversible) approved + retention (min 7 / max 400 days, monthly 365) | prod only, `enable_vault_lock = false` | backup module | WBD Security | Open |
| S3 cross-region replication of results / approved-worm (RPO minutes instead of 24 h) | not built: the DR copy of these buckets is the AWS Backup cross-region copy (daily, RPO 24 h). S3 replication only if WBD needs RPO in minutes | backup module (`enable_cross_region_copy`) | WBD | Proposed (Step 12) |
| WAF rate limit per IP | dev `2000` req/5 min | env tfvars `waf_rate_limit` | WBD Security | Open |
| WAF geo allow list (empty = no geo block) | `geo_allow_countries = []` | env tfvars | WBD Security | Open |
| WAF observe-only rules | `waf_count_only = []` | env tfvars | WBD Security | Open |

## Front door and Okta

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| App domain name per environment | dev `mmm-dev.example.wbd.com`; staging/prod WBD to provide | env tfvars `app_domain_name` | WBD DNS | Open |
| DNS: Route 53 zone in account or CNAME from WBD | `route53_zone_id = null` → use `terraform output dns_records_for_wbd` | `frontdoor.tf` | WBD DNS | Open |
| ACM certificate in **workload region** for `app_domain_name` | `alb_certificate_arn` | `alb` module HTTPS listener | WBD DNS / PKI | Open |
| Okta authorization server (issuer) per environment | `https://wbd.okta.com/oauth2/default` | env tfvars `okta_issuer` | WBD Identity | Open |
| Okta OIDC Web app client ID per environment | dev `0oa00000000000000000` | env tfvars `okta_client_id` | WBD Identity | Open |
| Okta OIDC client secret | none in Git – Secrets Manager `mmm/<env>/okta/alb-client` (`{"client_secret": "..."}`), then `okta_sign_in_enabled = true` | `frontdoor.tf` (ALB listener) | WBD Identity | Open |
| ALB session length (hours) | `12` | env tfvars `session_hours` | WBD Identity | Open |
| Okta OIDC redirect and sign-out URIs (from Terraform after apply) | `terraform output okta_app_settings` (`<app>/oauth2/idpresponse`, `<app>/`) | Okta OIDC app configuration | WBD Identity | Open – WBD enters values Terraform prints |
| Groups claim in the ID token / user info | `groups`, filter "Starts with `mmm-`" (forwarded by the ALB in `x-amzn-oidc-data`) | Okta app + API | WBD Identity | Open |
| Okta logout: is `client_id` accepted on `/v1/logout`? (the ALB does not give the app the ID token for `id_token_hint`) | `LOGOUT_URL` with `client_id` + `post_logout_redirect_uri` | UI env `LOGOUT_URL` | WBD Identity | Open |
| Okta group names → BU + role | see `docs/04-okta-mfa-app-login.md` | Okta group membership | WBD Identity | Open |
| Egress to PyPI through NAT (one-time DB bootstrap) or a WBD package mirror | – | `scripts/db-bootstrap.py` | WBD Network | Open |
| Internet-facing or internal-only app? | internet-facing public ALB + regional WAF + Okta OIDC at the ALB | `alb`, `waf-regional` | WBD Security | Open |

## Data and AI

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| Databricks workspace host | `https://dbc-00000000-0000.cloud.databricks.com` | tfvars, SSM `/mmm/<env>/databricks/host` | WBD Databricks | Open |
| Databricks account ID | `00000000-0000-0000-0000-000000000000` | Unity Catalog IAM role trust | WBD Databricks | Open |
| Databricks PrivateLink service name | `com.amazonaws.vpce.us-east-1.vpce-svc-00000000000000000` | databricks-access module | WBD Databricks | Open |
| Databricks service principal client ID (model-refresh Step Functions) | dev `…00000000c001` | tfvars `databricks_sp_client_id`, EventBridge connection | WBD Databricks | Open |
| Databricks service principal OAuth secret (model refresh) | not in Git – set on EventBridge connection `<prefix>-databricks` | `aws events update-connection` ([docs/05](05-secrets-and-config.md)) | WBD Databricks | Open |
| Databricks refresh job ID (Lakeflow / jobs API) | `0` until job exists | tfvars `databricks_refresh_job_id` | WBD Data / EY | Open |
| Databricks write-back job ID (predictions and lift to Gold after registration) | `0` until job exists | tfvars `databricks_writeback_job_id` | WBD Data / EY | Open |
| Drift check: metric, threshold per BU, schedule, auto-refresh on drift | score 0–1, `0.2`; daily `cron(0 7 * * ? *)`, off (`enable_model_monitor_schedule = false`); `auto_refresh_on_drift = false` | tfvars, `data/model-thresholds.yaml` `drift.threshold` | WBD Data science | Open |
| Databricks deploy SP client ID (Asset Bundle only) | WBD to provide | GitHub Environment `DATABRICKS_CLIENT_ID` via `setup-github.ps1 -DatabricksClientId` | WBD Databricks | Open |
| Third-party vendors needing API keys | `adstra`, `inscape` | env tfvars `third_party_vendors` | WBD Data owners | Open |
| Source feed delivery method (S3 / SFTP / API) | S3 drop to landing bucket | landing bucket policy | WBD Data owners | Open |
| Model refresh schedule + timezone | `cron(0 6 ? * MON *)`, `America/New_York` | tfvars `model_refresh_schedule`, `model_refresh_timezone` | WBD Data | Open |
| Enable scheduled refresh | `enable_model_refresh_schedule = false` | tfvars | WBD Data | Open |
| SageMaker training / optimizer instance types | training `ml.m5.2xlarge`; optimizer `ml.m5.xlarge` | env tfvars | WBD / EY sizing | Open |
| Enable the data platform per environment | `enable_data_platform = false` | env tfvars (Step 13) | User / WBD Data | Open |
| Business unit names (S3 prefixes, keys, models) | `usnetworks`, `streaming`, `theatrical` | env tfvars `business_units` (default) | WBD Data owners | Open |
| Unity Catalog storage-credential External ID | = `databricks_account_id` | Unity Catalog role trust (docs/10 §4) | WBD Databricks | Open |
| Databricks PrivateLink in use? | `enable_databricks_privatelink = false` | env tfvars | WBD Databricks / Network | Open |
| Model acceptance thresholds per business unit | MAPE ≤ 0.15/0.20, R² ≥ 0.80/0.75, R-hat ≤ 1.05, 0 negative channels | `data/model-thresholds.yaml` | WBD Data science / EY | Open |
| Model-promotion approver | `wbd-model-approver` | GitHub Environment `<env>-model-promotion` | WBD | Open |
| Release 1 gate sign-offs (G1–G5) | – | `docs/11-release-1-readiness.md` | EY delivery lead / WBD | Open |

## Release 2 GenAI (`enable_genai`)

| Input | Placeholder | Used in | Owner | Status |
|---|---|---|---|---|
| Approved external LLM providers | OpenAI, Anthropic, Google (`llm_providers` in tfvars) | `llm-gateway` module | WBD Responsible AI | Open |
| Provider API keys | `{"api_key":"..."}` per provider | Secrets Manager `mmm/<env>/llm/<provider>` | WBD / vendor contracts | Open |
| GenAI feature flag at runtime | `genai_enabled = false` | SSM `/mmm/<env>/genai_enabled` | WBD | Open |
| Token capacity / per-BU quotas | `1000000` tokens/day per BU | SSM `/mmm/<env>/genai/token_quota/<bu>` | WBD | Open |
| Guardrail thresholds (prompt attack, PII, grounding, relevance) | prompt attack `HIGH`, content `MEDIUM`, PII mask/block per module defaults; `genai_grounding_threshold = 0.75`, `genai_relevance_threshold = 0.75` | `bedrock-guardrails` module | WBD Responsible AI | Open |
| Lambda reserved concurrency for LLM proxy | `20` | tfvars `genai_reserved_concurrency` | WBD | Open |
| API Gateway account logging role | `manage_apigw_account_logging_role = true` | tfvars | WBD Cloud Platform | Open |

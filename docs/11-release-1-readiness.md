# 11 – Release 1 gate: readiness checklist and evidence

Release 1 (Steps 0–13) is the core platform. **Release 2 (Step 14, GenAI) does not start until
every item in section 1 is ticked and signed.** This document is the single place where the gate
evidence is collected; attach links (GitHub run, Jira, Confluence, screenshot) in the *Evidence*
column as each item is done.

Status values: `Open` · `In progress` · `Done` · `Waived (by …)`.

## 1. The gate

| # | Gate item | Owner | Sign-off by | Status | Evidence |
|---|---|---|---|---|---|
| G1 | Release 1 infra + CI/CD deployed to **dev, then staging, then prod**, same code (section 2) | EY DevOps | EY delivery lead | Open | |
| G2 | Data-team platform (Step 13) live in all three environments; model governance blocks a failing model and promotes a passing one only with approval (section 3) | EY DevOps + data team | WBD model-promotion approver | Open | |
| G3 | Production readiness checklist passed (section 4) | EY DevOps | WBD InfoSec + WBD Cloud Platform | Open | |
| G4 | Parallel run against the incumbent and UAT signed off; Release 1 go-live accepted in prod (section 5) | EY delivery lead | WBD business owner | Open | |
| G5 | WBD approves starting Release 2: approved external LLM providers, data-egress approval, and token capacity confirmed (section 6) | WBD | WBD Responsible AI + InfoSec | Open | |

Only when G1–G5 are `Done` (or formally waived) is the answer **"Release 1 complete / go for
Release 2"** recorded here:

| Decision | Name | Role | Date |
|---|---|---|---|
| Go for Release 2 | | | |

## 2. G1 – Rollout per environment

The same commit must be in all three accounts. The steps refer to the *Validate Step N* sections
of [`infra/environments/dev/README.md`](../infra/environments/dev/README.md); run them with the
environment's profile and name prefix (`mmm-dev-`, `mmm-stg-`, `mmm-prd-`).

| Item | dev | staging | prod |
|---|---|---|---|
| Client values in `terraform.tfvars` / `backend.tf` (no `# add actual value` left: `git grep -n -A1 "add actual value" -- infra/environments/<env>`) | ☐ | ☐ | ☐ |
| Step 1 bootstrap applied (state bucket, lock works) | ☐ | ☐ | ☐ |
| Steps 3–10 applied, plan shows **No changes** afterwards | ☐ | ☐ | ☐ |
| Step 11: GitHub Environment + variables set (`setup-github.ps1`), approvals configured | ☐ | ☐ | ☐ |
| Step 13: `enable_data_platform = true` applied; model-refresh state machine and schedules exist | ☐ | ☐ | ☐ |
| App release deployed by `deploy.yml` (dev `sha-…`, staging `vX.Y.Z-rcN`, prod `vX.Y.Z`) | ☐ | ☐ | ☐ |
| Smoke test green (`scripts/smoke.sh` against the public ALB URL: `/api/health` 200, `/` redirects to Okta) | ☐ | ☐ | ☐ |
| Okta sign-in on (`okta_sign_in_enabled = true`, secret `okta/alb-client` set, `SMOKE_CHECK_LOGIN=true`) | ☐ | ☐ | ☐ |
| Optimization dry run through the run queue green (`deploy.yml`, dev and staging) | ☐ | ☐ | – |
| Nightly drift check green for 3 nights in a row | ☐ | ☐ | ☐ |
| Release record artifact kept (image digests, task-definition revisions, approver) | ☐ | ☐ | ☐ |

Check that the three environments run the same images:

```powershell
$profiles = @{ dev = "mmm-dev-devops"; stg = "mmm-stg-devops"; prd = "mmm-prd-readonly" }   # docs/02 §3
foreach ($e in "dev","stg","prd") {
  $env:AWS_PROFILE = $profiles[$e]
  foreach ($s in "api","ui") {
    $td = aws ecs describe-services --cluster "mmm-$e-ecs" --services "mmm-$e-$s" --query "services[0].taskDefinition" --output text
    $img = aws ecs describe-task-definition --task-definition $td --query "taskDefinition.containerDefinitions[?name=='app'].image | [0]" --output text
    "{0,-4} {1,-17} {2}" -f $e, $s, $img
  }
}
# staging and prod show the same version tag; the digests in the release records match
```

Infrastructure code is identical (CI runs this on every push):

```powershell
.\scripts\sync-environments.ps1 -Check
```

## 3. G2 – Data-team platform and model governance

Run *Validate Step 13 → With AWS* in each environment (see [docs/10 §9](10-data-platform-and-model-governance.md#9-enabling-verification-troubleshooting)).
When the data engineers ship the Glue scripts, confirm `glue.yml` uploaded them to each environment.

| Check | dev | staging | prod |
|---|---|---|---|
| `glue.yml` uploaded the job scripts to `glue-assets/scripts/` (no seed script left) | ☐ | ☐ | ☐ |
| `databricks/export-sp` filled and `databricks_export_job_ids` set; `StartExport` reaches Databricks and the export lands in `raw/databricks/<bu>/` | ☐ | ☐ | ☐ |
| Bronze → Silver (Data Quality passes) → Gold → export-training / export-rds succeed; `rds-export/<bu>/<refresh_id>/_manifest.json` written; PublishReferenceData loads the rows into RDS (`mmm_app`) | ☐ | ☐ | ☐ |
| SageMaker lineage context `mmm-<env_short>-refresh-<refresh_id>` exists: 4 inputs (raw export, reference data, training snapshot, training job) `ContributedTo` it (`aws sagemaker list-associations --destination-arn <context>`), it `Produced` the model package (`--source-arn <context>`) | ☐ | ☐ | ☐ |
| Scheduled or on-demand refresh starts `mmm-<env>-model-refresh` | ☐ | ☐ | ☐ |
| Upload without the business-unit KMS key to landing is denied | ☐ | ☐ | ☐ |
| On-demand trigger (`scripts/trigger-model-refresh.sh`) starts one execution per BU | ☐ | ☐ | ☐ |
| `evaluation.json` and `curves/` written under `models/evaluation/<bu>/<refresh_id>/` | ☐ | ☐ | ☐ |
| Model package registered `PendingManualApproval` with ModelMetrics | ☐ | ☐ | ☐ |
| Unity Catalog role phase 2 done; Databricks *Validate configuration* passes | ☐ | ☐ | ☐ |
| Optimizer reads approved curves from `s3://<models>/curves/<bu>/` after promote | ☐ | ☐ | ☐ |
| Failing package tagged `governance_status=failed` and **Rejected** | ☐ | ☐ | ☐ |
| Passing package waits in `<env>-model-promotion`, approved by someone other than the requester | ☐ | ☐ | ☐ |
| Approval publishes `models/baseline/<bu>/` and writes `approval.json` next to `evaluation.json` | ☐ | ☐ | ☐ |
| `PublishModelResults` wrote predictions, lift and evaluation to RDS after registration | ☐ | ☐ | ☐ |
| Model monitor run per BU succeeds; `ModelDrift` metric visible; then `enable_model_monitor_schedule = true` | ☐ | ☐ | ☐ |
| Model rollback re-publishes previous curves and baseline (docs/10 §7) | ☐ | – | ☐ |
| `data/model-thresholds.yaml` holds the **signed-off Week-1 thresholds** (not placeholders) | ☐ (one file for all) | | |

## 4. G3 – Production readiness checklist

Most tests run in **staging** (production-like, same code); the prod column is for checks that
must be seen in prod itself.

| # | Item | How to prove it | Where | Owner | Status | Evidence |
|---|---|---|---|---|---|---|
| R1 | WBD architecture and security design approval recorded | Design pack (deployment diagram, ADRs, threat model, RPO/RTO) approved in writing | – | EY DevOps | Open | |
| R2 | Penetration test done; no open Critical/High | WBD-approved tester against staging (and prod ALB if required); findings tracked to closure | staging | WBD InfoSec | Open | |
| R3 | All scans clean or exceptions approved | Last `repo-checks`, `api-ci`, `ui-ci`, `optimizer-ci`, `training-ci`, `terraform` (Checkov) runs green on the release commit; DAST (e.g. OWASP ZAP baseline) against staging; ECR enhanced-scan findings for the release images | staging | EY DevOps | Open | |
| R4 | Encryption at rest and TLS 1.2+ everywhere | Section 4.1 commands | staging, prod | EY DevOps | Open | |
| R5 | Backups running; restore test met RPO/RTO | AWS Backup jobs `COMPLETED` for 7 days; RDS point-in-time restore and S3 restore ([docs/08 §3–4](08-backup-and-dr.md)); measured times recorded in section 4.2 | staging | EY DevOps | Open | |
| R6 | Failover tested | Section 4.3 | staging | EY DevOps | Open | |
| R7 | Performance targets met (or deviations accepted by WBD) | Section 4.4 | staging | EY DevOps + app teams | Open | |
| R8 | Dashboards and alerts live; on-call ready | Section 4.5 | staging, prod | EY DevOps | Open | |
| R9 | Runbooks written; rollback practised | Runbooks for deploy, rollback, DB restore, ECS task stuck, secret/cert rotation, model rollback, break-glass ([docs/runbooks](runbooks/README.md)); app rollback by dispatch in staging ([docs/09 §6](09-cicd-pipelines.md#6-everyday-operations)) | staging | EY DevOps | Open | |
| R10 | Access reviewed; test credentials rotated | Permission-set assignments reviewed with WBD Identity; no IAM users or access keys (`aws iam list-users`); test secrets rotated (`docs/05 §6`); break-glass login raises the alert | all | EY DevOps + WBD Identity | Open | |
| R11 | Okta login, MFA, step-up MFA and business-unit isolation | [docs/04 §8](04-okta-mfa-app-login.md#8-testing); a user of one BU cannot read another BU's scenarios | staging, prod | app team + EY DevOps | Open | |
| R12 | AWS Well-Architected review; high-risk items closed | Well-Architected Tool workload for prod (security, reliability, cost) | prod | EY DevOps | Open | |
| R13 | Cost controls in place | Budgets and anomaly monitor active; Fargate vCPU quota raised for the load-tested maximum | all | EY DevOps | Open | |
| R14 | CAB change approved for go-live | WBD change ticket; its number is in the `vX.Y.Z` tag message | prod | EY delivery lead | Open | |

### 4.1 Encryption and TLS (R4)

Run with `mmm-stg-devops` (staging) or `mmm-prd-readonly` (prod, replace `stg` with `prd`).

```powershell
$p = "mmm-stg"
# RDS: encrypted instance, TLS via proxy
aws rds describe-db-instances --db-instance-identifier "$p-postgres" --query "DBInstances[0].[StorageEncrypted,KmsKeyId,DeletionProtection,MultiAZ]"
aws rds describe-db-proxies --db-proxy-name "$p-postgres-proxy" --query "DBProxies[0].RequireTLS"   # true
# SQS run queue: KMS key
aws sqs get-queue-attributes --queue-url (aws sqs get-queue-url --queue-name "$p-optimization-requests" --query QueueUrl --output text) --attribute-names KmsMasterKeyId
# S3: every project bucket has default encryption and blocks public access
aws s3api list-buckets --query "Buckets[?starts_with(Name,'wbd-mmm-stg-')].Name" --output text -split "\s+" | ForEach-Object {
  "{0,-45} {1,-8} {2}" -f $_, (aws s3api get-bucket-encryption --bucket $_ --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" --output text),
    (aws s3api get-public-access-block --bucket $_ --query "PublicAccessBlockConfiguration.RestrictPublicBuckets" --output text)
}
# ALB: TLS 1.2+ policy
$alb = aws elbv2 describe-load-balancers --names "$p-alb" --query "LoadBalancers[0].LoadBalancerArn" --output text
aws elbv2 describe-listeners --load-balancer-arn $alb --query "Listeners[].[Protocol,Port,SslPolicy]"   # HTTPS 443 ELBSecurityPolicy-TLS13-1-2-2021-06
# TLS 1.1 is refused (expect a handshake failure)
curl.exe -s -o NUL -w "%{http_code}`n" --tls-max 1.1 https://<app domain>/
```

### 4.2 Restore test record (R5)

| Test | Date | Target RPO / RTO (docs/08 §1) | Measured | Pass |
|---|---|---|---|---|
| RDS point-in-time restore (staging) | | ≤ 5 min / 1 h | | |
| S3 single object (versioning) | | 0 / 15 min | | |
| S3 bucket restore (AWS Backup) | | 24 h / 2 h | | |
| Full environment rebuild from code (staging) | | 24 h / 4 h | | |

### 4.3 Failover tests (R6, staging)

Watch the platform dashboard and the `mmm-stg-api-5xx-rate` alarm during each test. A test passes when
the API keeps answering (brief errors during an RDS Multi-AZ failover are expected and must recover
without manual action).

```powershell
$p = "mmm-stg"
# 1. RDS Multi-AZ failover (about 60–120 s; RDS Proxy keeps the endpoint)
aws rds reboot-db-instance --db-instance-identifier "$p-postgres" --force-failover
# 2. Kill an API task: the service starts a replacement, ALB keeps serving from the others
$t = aws ecs list-tasks --cluster "$p-ecs" --service-name "$p-api" --query "taskArns[0]" --output text
aws ecs stop-task --cluster "$p-ecs" --task $t --reason "R6 failover test"
# 3. Kill a UI task (same pattern)
$t = aws ecs list-tasks --cluster "$p-ecs" --service-name "$p-ui" --query "taskArns[0]" --output text
aws ecs stop-task --cluster "$p-ecs" --task $t --reason "R6 failover test"
# 4. Abort a running optimization execution: UI/API should show failure; user can retry (new run_id)
$sm = aws stepfunctions list-state-machines --query "stateMachines[?name=='$p-optimization'].stateMachineArn" --output text
$ex = aws stepfunctions list-executions --state-machine-arn $sm --status-filter RUNNING --max-results 1 --query "executions[0].executionArn" --output text
if ($ex -ne "None") { aws stepfunctions stop-execution --execution-arn $ex --cause "R6 test" }
```

Loss of a whole AZ: with WBD's approval, use AWS Fault Injection Service
(`aws:network:disrupt-connectivity` on one AZ's private-app subnets) for 10 minutes. Without
approval, record the tabletop result instead.

| Test | Date | Impact seen | Recovered without action | Pass |
|---|---|---|---|---|
| RDS Multi-AZ failover | | | | |
| Run queue: more requests than `max_concurrent_runs` queue and start as slots free up | | | | |
| API task killed | | | | |
| UI task killed | | | | |
| Optimization execution stopped | | | | |
| AZ loss (FIS or tabletop) | | | | |

### 4.4 Performance (R7, staging)

Targets are the draft values in RFP Appendix A (WBD to confirm). Load tool: k6 or Locust, run from
inside the WBD network or a task in the staging VPC, against the **ALB / app domain** URL, with a test user
per business unit. The app teams provide the request scenarios (create scenario, optimize,
what-if, compare, export).

| Scenario | Target | 20 users | 40 users | 60 users | Pass |
|---|---|---|---|---|---|
| Standard optimization run | < 2 min | | | | |
| Large / unconstrained run | < 10 min | | | | |
| What-if simulation (p95, `WhatIfDurationMs`) | < 10 s | | | | |
| API p95 latency (non-optimization calls) | agree with app team | | | | |
| API 5xx rate | < 2 % | | | | |
| Availability during the test | ≥ 99.5 % | | | | |

Record the tuned values after the test and copy them into the staging and prod tfvars / `ecs/<env>/*.json`:

| Setting | Before | After |
|---|---|---|
| API task CPU / memory, min / max tasks | | |
| UI task CPU / memory, min / max tasks | | |
| SageMaker optimizer instance type / max runtime | | |
| RDS instance class / storage, RDS Proxy max connections % | | |
| `max_concurrent_runs`, `max_queue_wait_minutes` | | |
| Fargate vCPU quota requested | | |

### 4.5 Alerts reach on-call (R8)

```powershell
$p = "mmm-stg"
aws sns list-subscriptions-by-topic --topic-arn (aws sns list-topics --query "Topics[?ends_with(TopicArn,':$p-alerts')].TopicArn | [0]" --output text) --query "Subscriptions[].[Protocol,Endpoint,SubscriptionArn]"   # all confirmed
aws cloudwatch describe-alarms --alarm-name-prefix "$p-" --query "MetricAlarms[].[AlarmName,StateValue]" --output table
# fire a test alert; it must reach the on-call channel, then return to OK on the next evaluation
aws cloudwatch set-alarm-state --alarm-name "$p-cert-expiry-alb" --state-value ALARM --state-reason "Release 1 gate test"
```

Also confirm: one `run_id` can be followed in Splunk across API, optimization Step Functions, publisher,
and audit events; the CloudWatch dashboard `mmm-<env>-platform` shows API, ECS, RDS, Step Functions,
Lambda, and WAF; every alarm description points to a runbook.

## 5. G4 – Parallel run, UAT and go-live

| Item | Owner | Status | Evidence |
|---|---|---|---|
| Week-1 comparison tolerances agreed with WBD (ranking reversals, allocation direction, channel lift) | EY data science + WBD | Open | |
| Staging loaded with the approved production-like Databricks clone (WBD Privacy approval) | data team | Open | |
| Parallel run: same scenarios on the incumbent and on staging; differences within tolerance or explained | EY data science | Open | |
| UAT by WBD planners in staging; Critical/High defects closed | EY delivery lead | Open | |
| Change freeze in staging during UAT and the parallel run | EY DevOps | Open | |
| Go/no-go meeting held; CAB approved (R14) | EY delivery lead | Open | |
| Prod cutover: `vX.Y.Z` deployed, smoke test (login, optimization, compare, override, export) | EY DevOps | Open | |
| Hypercare started; incumbent kept read-only with a rollback window | EY + WBD | Open | |
| WBD accepts Release 1 go-live | WBD business owner | Open | |

## 6. G5 – Inputs WBD must give before Release 2

These are the Step 14 inputs; they are tracked in [docs/01](01-client-inputs-tracker.md#data-and-ai).

| Input | Used for | Status |
|---|---|---|
| WBD approval to send planner-visible data to external LLM APIs (data egress) | `enable_genai`, provider keys | Open |
| Approved providers (`openai`, `anthropic`, `google`, …) | `llm_providers` tfvar | Open |
| Provider API keys | Secrets Manager `mmm/<env>/llm/<provider>` (`{"api_key":"..."}`) | Open |
| Token capacity and per-business-unit quotas | `genai_token_quotas` → SSM `/mmm/<env>/genai/token_quota/<bu>` (API enforcement) | Open |
| Responsible AI review outcome (guardrail thresholds: prompt attack, PII, grounding) | `bedrock-guardrails` module | Open |
| `genai_reserved_concurrency`, `manage_apigw_account_logging_role` | LLM gateway Lambda / API Gateway logging | Open |
| Monthly platform budget (includes GenAI provider spend) | `monthly_budget_usd`, Cost Explorer | Open |

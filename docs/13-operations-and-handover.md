# 13 – Operations and handover

How the platform is run after go-live, and how EY hands it over to the WBD (or managed-service)
operations team. Procedures for incidents and changes: [runbooks/](runbooks/README.md).

## 1. Who does what (proposal – confirm with WBD, docs/01)

| Activity | EY DevOps (hypercare) | WBD platform / ops team (after handover) | WBD app owner | WBD security |
|---|---|---|---|---|
| Alarms, on-call, runbooks | R | R (after handover) | I | I (security alerts: R) |
| Releases to prod | R (executes) | R (after handover) | A (approves) | C |
| Terraform changes, drift | R | R | I | C (IAM, network) |
| Patching (images, dependencies) | R | R | C | I |
| Access reviews | C | R | A | C |
| Restore / DR tests | R | R | A | I |
| Model promotion | C | C | A (model approvers) | I |
| GenAI policy (providers, guardrail, quotas) | C | C | A | A |

R = responsible, A = approves, C = consulted, I = informed.

## 2. Ongoing operations schedule

| When | Task | How | Evidence |
|---|---|---|---|
| Daily | Check alarms in ALARM and overnight alerts | `aws cloudwatch describe-alarms --state-value ALARM --alarm-name-prefix mmm-prd`; dashboard `mmm-prd-platform` | – |
| After every release (dev, staging) | Optimization dry run (automatic) | `deploy.yml` runs `scripts/dry-run-optimization.sh` when the optimizer or publisher changed; a failure rolls the release back | Release record, Actions log |
| Nightly 03:00 UTC | Drift check (automatic) | `terraform.yml` schedule plans every environment; a red run means a change outside Terraform → [pipeline-failure.md](runbooks/pipeline-failure.md) | Actions history |
| Nightly | Backups (automatic) | AWS Backup plan `mmm-<env>-daily`; alarm on failed backup jobs | Backup console |
| Weekly (Mon) | Vulnerability fixes | Merge Dependabot PRs (**github-actions** and **pip** under `/scripts`, per [dependabot.yml](../.github/dependabot.yml)); triage ECR Inspector findings (`aws inspector2 list-findings --filter-criteria '{"ecrImageRepositoryName":[{"comparison":"PREFIX","value":"mmm/"}],"severity":[{"comparison":"EQUALS","value":"CRITICAL"}]}'`); fixable Critical/High in prod images → release within 7 days (High 30 days) | PR links, release record |
| Weekly | Cost check | Budget `mmm-<env>-monthly` (platform); Cost Anomaly emails | – |
| Monthly | Patch base images | App teams bump base image digests in Dockerfiles → CI → normal release. Fargate platform is patched by AWS (`platform_version = LATEST` on deploy) | Release record |
| Monthly | Review Security Hub / GuardDuty | Findings for the MMM accounts with WBD security | Ticket |
| Monthly | Minor version upgrades | RDS PostgreSQL minor (maintenance window), Terraform provider (`terraform init -upgrade` in dev → sync → PR), GitHub Actions via Dependabot | PR |
| Quarterly | Access review | Permission-set assignments per account with WBD Identity; GitHub environment reviewers; no IAM users / keys (`aws iam list-users` empty); break-glass test ([break-glass.md](runbooks/break-glass.md)) | Signed review |
| Quarterly | Restore test | RDS point-in-time + S3 restore in staging ([docs/08 §7](08-backup-and-dr.md#7-regular-tests)), record RPO / RTO achieved | Restore record (docs/11 §4.2 format) |
| Quarterly | Rotate long-lived tokens due | [rotation.md](runbooks/rotation.md) schedule (Okta ALB client secret, LLM provider keys, Splunk HEC, third-party vendors) | Ticket |
| Monthly | Drift review | `mmm-<env>-training` dashboard drift widgets per business unit; agree with data science whether a refresh is needed ([model-drift.md](runbooks/model-drift.md)) | – |
| Twice a year | DR exercise | Rebuild staging from code + restore data (docs/08 §5); prod region failover rehearsal if WBD approved the DR region (§6) | DR report |
| Twice a year | Failover tests | RDS Multi-AZ failover, kill API/UI tasks, optimization abort test (docs/11 §4.3) in staging | Test record |
| Yearly | Major upgrades | PostgreSQL major, Python runtime on Lambda/images, Terraform major – planned changes with a staging soak | Change ticket |
| Before planning season | Scale up | [scale-planning-season.md](runbooks/scale-planning-season.md) | PR |

## 3. Alarm → runbook

Platform alarms use prefix `mmm-<env>-`. Each state machine adds `-failed` and `-throttled`, each
Lambda `-errors`. Full list with thresholds: [monitoring README](../infra/modules/monitoring/README.md).

| Alarm / alert | Runbook |
|---|---|
| `api-no-healthy-targets`, `ui-no-healthy-targets`, `api-5xx-rate`, `availability`, EventBridge `ecs-deployment-failed`, `ecs-service-error` | [ecs-task-stuck.md](runbooks/ecs-task-stuck.md), [rollback.md](runbooks/rollback.md) |
| `whatif-p95` | [ecs-task-stuck.md](runbooks/ecs-task-stuck.md), [scale-planning-season.md](runbooks/scale-planning-season.md) |
| `optimization-failed`, `results-publisher-errors`, `optimization-runtime-max`, `optimization-standard-p95` | [optimization-run-failed.md](runbooks/optimization-run-failed.md); runtime: [scale-planning-season.md](runbooks/scale-planning-season.md) (`optimizer_cpu` / `optimizer_memory`) |
| EventBridge `optimizer-task-not-started` | [optimization-run-failed.md](runbooks/optimization-run-failed.md) (image pull, secret, Fargate capacity) |
| `runs-oldest-request`, `runs-expired-requests` | [scale-planning-season.md](runbooks/scale-planning-season.md) (`max_concurrent_runs`); [optimization-run-failed.md](runbooks/optimization-run-failed.md) if runs are not finishing |
| `runs-dlq-not-empty`, `runs-dispatcher-errors`, `runs-dispatcher-throttles` | [optimization-run-failed.md](runbooks/optimization-run-failed.md) (dispatcher, DLQ redrive) |
| `optimization-throttled`, `model-refresh-throttled`, `model-monitor-throttled` | [scale-planning-season.md](runbooks/scale-planning-season.md) (Step Functions quota) |
| `model-refresh-failed`, `model-refresh-overdue` | [model-refresh-failed.md](runbooks/model-refresh-failed.md) |
| `databricks-export-errors` | [databricks-export-failed.md](runbooks/databricks-export-failed.md) |
| EventBridge `glue-job-failed`, `glue-data-quality-failed` | [glue-job-failed.md](runbooks/glue-job-failed.md) |
| `model-monitor-failed`, `model-drift-<bu>` | [model-drift.md](runbooks/model-drift.md) |
| EventBridge `model-package-state` (version created / approved / rejected) | [model-rollback.md](runbooks/model-rollback.md); a rejection lists the failed thresholds |
| `rds-cpu`, `rds-connections`, `rds-read-latency`, `rds-write-latency`, `rds-free-storage` | Larger `rds_instance_class` or `rds_max_allocated_storage` / tune queries (PR; class change = short outage, Multi-AZ fails over first); [db-restore.md](runbooks/db-restore.md) if data is affected |
| `cert-expiry-alb` | [rotation.md](runbooks/rotation.md) |
| EventBridge `backup-job-failed` | [docs/08](08-backup-and-dr.md); re-run the job on demand |
| Budget email `mmm-<env>-monthly`, Cost Anomaly email | Cost dashboard `mmm-<env>-cost`; [scale-planning-season.md](runbooks/scale-planning-season.md) to scale back down |
| `splunk-delivery`, `splunk-freshness` | HEC token / endpoint ([rotation.md](runbooks/rotation.md)); failed records in the log bucket |
| `llm-gateway-5xx`, `llm-gateway-4xx`, `llm-gateway-latency-p95`, `genai-guardrail-interventions`, `genai-tokens-<bu>` | [genai.md](runbooks/genai.md) |
| EventBridge `guardduty-high`, `breakglass-used` | [security-incident.md](runbooks/security-incident.md), [break-glass.md](runbooks/break-glass.md) |

**On-call daily check (prod):** `describe-alarms` in ALARM; scan SNS topic subscriptions; open the
`mmm-prd-platform` dashboard (alarm list, requests and 5xx, ECS tasks, RDS, Step Functions,
Lambda, WAF), then `mmm-prd-api-ui`, `mmm-prd-optimization` (incl. run queue), `mmm-prd-rds`, `mmm-prd-cost`
(and `-training`, `-genai` when those are on) as needed. If Splunk shipping is on, spot-check
freshness for `api`, `sfn-optimization`, and `publisher` log groups.

## 4. Handover (knowledge transfer)

### Sessions (about 2 weeks, recorded)

| # | Topic | Material | Hands-on (in staging) |
|---|---|---|---|
| 1 | Architecture, accounts, naming, tags | README, docs/00–02 | SSO login to every account |
| 2 | Terraform layout, modules, dev → sync → staging/prod, state | `infra/`, docs/03, environment READMEs | Small PR → plan → apply in dev |
| 3 | Secrets, config, IAM model, OIDC | docs/03, 05, 06 | Fill a secret, read a parameter |
| 4 | CI/CD and releases | docs/07, 09, `runbooks/deploy.md` | Cut an rc, promote, roll back by dispatch |
| 5 | Monitoring, logging, Splunk, alarms | [monitoring README](../infra/modules/monitoring/README.md), §3 above | Fire a test alarm, follow it to the runbook |
| 6 | Backup, restore, DR | docs/08, `runbooks/db-restore.md` | Point-in-time restore next to staging |
| 7 | Data platform and model governance | docs/10, `runbooks/model-rollback.md` | On-demand model refresh, governance evaluate/promote drill |
| 8 | GenAI (if Release 2 is live) | docs/12, `runbooks/genai.md` | Flag off / on |
| 9 | Security operations | `runbooks/security-incident.md`, `runbooks/break-glass.md` | Break-glass drill |
| 10 | Shadowing → reverse shadowing | all runbooks | WBD engineer runs a release and an incident drill with EY watching |

### Handover checklist

| Item | Done |
|---|---|
| GitHub: WBD ops team are repo admins / environment reviewers; EY access reduced to what hypercare needs | ☐ |
| AWS: WBD ops team in the DevOps / ReadOnly / BreakGlass groups; EY assignments end at hypercare exit | ☐ |
| Alerts: `mmm-<env>-alerts` subscribed by WBD on-call (email / paging tool); EY addresses removed at exit | ☐ |
| Budgets and anomaly emails go to WBD owners (`budget_alert_emails`) | ☐ |
| All `# add actual value` placeholders replaced (`git grep -n "add actual value"` shows only documentation) | ☐ |
| docs/01 tracker: every row Closed or accepted as an open risk by WBD | ☐ |
| Release 1 gate (docs/11) and, if live, Release 2 sign-off archived | ☐ |
| Last restore test and DR exercise records handed over | ☐ |
| Open vulnerabilities and technical debt list reviewed with WBD (owner + due date) | ☐ |
| Runbooks walked through and accepted by the WBD ops lead | ☐ |
| Hypercare period agreed (proposal: 4 weeks after go-live), then exit sign-off | ☐ |

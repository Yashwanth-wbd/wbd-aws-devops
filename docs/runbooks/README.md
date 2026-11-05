# Runbooks

Step-by-step procedures for the MMM platform. Ongoing operations, the schedule and the handover
are in [docs/13](../13-operations-and-handover.md).

## Before you start (every runbook)

```bash
# Pick the environment; P is the name prefix, E the SSM / env short name
export E=prd P=mmm-prd AWS_PROFILE=mmm-prd-readonly    # dev: mmm-dev-devops, staging: mmm-stg-devops
aws sso login --sso-session wbd && aws sts get-caller-identity
```

- **Look first with read-only** (`mmm-prd-readonly`). Use `mmm-prd-devops` only for the change step,
  `BreakGlass` only as in [break-glass.md](break-glass.md).
- Production changes go through the pipeline (PR / tag / dispatch) wherever a runbook offers it.
  A manual change in AWS is followed by a PR so Terraform matches reality; the nightly drift
  check (03:00 UTC) reports anything left behind.
- Write what you did, with times (UTC), in the incident or change ticket.

## Index

| Runbook | Use when | Typical alarm / signal |
|---|---|---|
| [deploy.md](deploy.md) | Releasing a version to dev, staging, prod | – |
| [rollback.md](rollback.md) | A release is bad (app, UI, infra, data, model, GenAI) | `api-5xx-rate`, `ecs-deployment-failed`, users |
| [scale-planning-season.md](scale-planning-season.md) | Before the upfront / planning season or a known peak | `whatif-p95`, `aurora-cpu`, `aurora-acu-max`, `aurora-connections`, `optimization-runtime-max`, `optimization-throttled` |
| [optimization-run-failed.md](optimization-run-failed.md) | An optimization Step Functions execution failed | `mmm-<env>-optimization-failed`, `results-publisher-errors`, stuck runs in the UI, failed post-release dry run |
| [model-refresh-failed.md](model-refresh-failed.md) | A model refresh (Databricks → SageMaker training → registry) failed | `mmm-<env>-model-refresh-failed`, `model-refresh-overdue` |
| [cognito-idp-outage.md](cognito-idp-outage.md) | Users cannot sign in (Cognito / Okta) | users, smoke test login check |
| [db-restore.md](db-restore.md) | Data was deleted or corrupted; database lost | users, AWS Health, Aurora alarms |
| [ecs-task-stuck.md](ecs-task-stuck.md) | Tasks do not start, do not stop, or a deployment hangs | `ecs-service-error`, `api-no-healthy-targets`, `ui-no-healthy-targets` |
| [rotation.md](rotation.md) | Rotating secrets, tokens, certificates | `cert-expiry-*`, schedule |
| [pipeline-failure.md](pipeline-failure.md) | A GitHub Actions workflow is red | GitHub notification |
| [model-rollback.md](model-rollback.md) | A promoted MMM model gives bad results | planners, governance report, `model-package-state` (Rejected) |
| [genai.md](genai.md) | GenAI on / off, GenAI alarms, guardrail issues (Release 2) | `llm-gateway-5xx`, `llm-gateway-4xx`, `llm-gateway-latency-p95`, `genai-guardrail-interventions`, `genai-tokens-<bu>` |
| [security-incident.md](security-incident.md) | Suspected compromise, leaked secret, GuardDuty HIGH | `guardduty-high`, secret scan |
| [break-glass.md](break-glass.md) | Emergency change in prod when the pipeline or normal access cannot be used | `breakglass-used` |

## Severity and response (proposal – confirm with WBD, docs/01)

| Severity | Example | Response | Who |
|---|---|---|---|
| SEV1 | Prod down or data exposed | 15 min, continuous until mitigated; status every 30 min | On-call DevOps + EY lead + WBD app owner (+ WBD security for data) |
| SEV2 | Prod degraded (slow what-ifs, optimization failures, one BU affected) | 1 h, same business day fix | On-call DevOps |
| SEV3 | Non-prod broken, single alarm with workaround | Next business day | DevOps team |

Alerts arrive through SNS topic `mmm-<env>-alerts` (email; add the on-call tool subscription when WBD names it).

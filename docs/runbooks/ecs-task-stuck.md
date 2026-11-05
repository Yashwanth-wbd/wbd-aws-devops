# Runbook: ECS task stuck

Cluster `mmm-<env>-ecs`; services `mmm-<env>-{api,ui}`; one-off tasks `migrate`, `platform-check`;
logs `/ecs/mmm-<env>/<service>`. Signals: `ecs-service-error` and `ecs-deployment-failed` events,
`api-no-healthy-targets`, `ui-no-healthy-targets`.

## 1. What is the service doing?

```bash
S=api   # or ui
aws ecs describe-services --cluster $P-ecs --services $P-$S \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,deployments:deployments[].[status,rolloutState,taskDefinition,failedTasks],events:events[:8].message}'
aws ecs list-tasks --cluster $P-ecs --service-name $P-$S --desired-status STOPPED --max-items 5
aws ecs describe-tasks --cluster $P-ecs --tasks <task arn> \
  --query 'tasks[0].{stopped:stoppedReason,code:stopCode,containers:containers[].[name,exitCode,reason]}'
```

## 2. Match the symptom

| Symptom (service events / stoppedReason) | Cause | Fix |
|---|---|---|
| `CannotPullContainerError` | Image tag missing in this ECR, or no route to ECR / S3 endpoints | Check the tag exists; check endpoints `mmm-<env>-vpce-ecr-*` are `available` |
| `ResourceInitializationError: unable to pull secrets` | Secret empty / deleted, or KMS / endpoint problem | `aws secretsmanager describe-secret --secret-id mmm/<env>/<name>`; fill it (docs/05 §5) |
| Tasks start, then `Essential container exited` (exit 1) | App crash at start (config, DB unreachable) | Read `/ecs/mmm-<env>/<service>`; roll back ([rollback.md](rollback.md)) |
| `Task failed ELB health checks` | App not answering `/api/health` or `/healthz` within the grace period | App logs; check Aurora proxy; roll back |
| `OutOfMemoryError: Container killed` | Memory limit too low | Raise `memory` in `ecs.tf` (PR) |
| `unable to place a task … capacity` / Spot interruptions | Fargate capacity or quota | Wait / retry; check quotas ([scale-planning-season.md](scale-planning-season.md)) |
| Deployment `IN_PROGRESS` for > 30 min | New tasks keep failing; circuit breaker | Fix cause above; or roll back to the previous revision now |
| Migrate task stuck | Bootstrap or Alembic hang | Logs `/ecs/mmm-<env>/migrate`; check proxy connectivity |

Optimization failures are **not** ECS services – see [optimization-run-failed.md](optimization-run-failed.md).

## 3. Look inside a running task (ECS Exec, audited)

```bash
aws ecs execute-command --cluster $P-ecs --task <task arn> --container app --interactive --command "/bin/sh"
```

Sessions are logged to the exec audit log group (KMS). Prod: only with an incident ticket.

## 4. Afterwards

If you changed anything by hand (desired count), make sure the next apply / deploy puts the service
back to the code state.

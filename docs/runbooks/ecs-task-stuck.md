# Runbook: ECS task stuck

Cluster `mmm-<env>-ecs`; services `mmm-<env>-{api,whatif-worker,optimizer-worker,genai-gateway}`;
logs `/ecs/mmm-<env>/<service>`. Signals: `ecs-service-error` and `ecs-deployment-failed` events,
`api-no-healthy-targets`, `mmm-<env>-<service>-backlog-high`.

## 1. What is the service doing?

```bash
S=api   # or whatif-worker, optimizer-worker, genai-gateway
aws ecs describe-services --cluster $P-ecs --services $P-$S \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,deployments:deployments[].[status,rolloutState,taskDefinition,failedTasks],events:events[:8].message}'
aws ecs list-tasks --cluster $P-ecs --service-name $P-$S --desired-status STOPPED --max-items 5
aws ecs describe-tasks --cluster $P-ecs --tasks <task arn> \
  --query 'tasks[0].{stopped:stoppedReason,code:stopCode,containers:containers[].[name,exitCode,reason]}'
```

## 2. Match the symptom

| Symptom (service events / stoppedReason) | Cause | Fix |
|---|---|---|
| `CannotPullContainerError` | Image tag missing in this ECR, or no route to ECR / S3 endpoints | Check the tag exists (`aws ecr describe-images --repository-name mmm/<app> --image-ids imageTag=<tag>`); check endpoints `mmm-<env>-vpce-ecr-*` are `available` |
| `ResourceInitializationError: unable to pull secrets` | Secret empty / deleted, or KMS / endpoint problem | `aws secretsmanager describe-secret --secret-id mmm/<env>/<name>`; fill it (docs/05 §5); a task with an empty secret never starts |
| Tasks start, then `Essential container exited` (exit 1) | App crash at start (config, DB unreachable) | Read the first lines of `/ecs/mmm-<env>/<service>`; roll back ([rollback.md](rollback.md)) |
| `Task failed ELB health checks` | App not answering `/health` on 8080 within the grace period | App logs; check the DB / cache; roll back |
| `OutOfMemoryError: Container killed` | Memory limit too low for the job | Raise `memory` for that service in `ecs.tf` (PR); redrive the job from the DLQ |
| `unable to place a task … capacity` / Spot interruptions | Fargate capacity or quota | Wait / retry; check quotas ([scale-planning-season.md](scale-planning-season.md)) |
| Deployment `IN_PROGRESS` for > 30 min | New tasks keep failing; the circuit breaker needs several failures | Fix cause above; or roll back to the previous revision now |
| Task does not stop (`DEACTIVATING` / `STOPPING` long) | Worker protected while running a job (task scale-in protection), or ignores SIGTERM | Wait for the job (protection ends with it). If the job is stuck: `aws ecs update-task-protection --cluster $P-ecs --tasks <arn> --no-protection-enabled`, then `aws ecs stop-task` – the job returns to the queue after the visibility timeout |
| Optimizer stays at 0 with a backlog | Autoscaling alarm / target issue | `aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id service/$P-ecs/$P-optimizer-worker` |
| genai-gateway healthy but API gets connection errors | Service Connect: proxy not registered, or SG | `deployments[0].serviceConnectConfiguration`; `ecs-agent` endpoint available; SG rule `api → genai` exists |

## 3. Look inside a running task (ECS Exec, audited)

```bash
aws ecs execute-command --cluster $P-ecs --task <task arn> --container app --interactive --command "/bin/sh"
```

Sessions are logged to the exec audit log group (KMS). Prod: only with an incident ticket.

## 4. Afterwards

If you changed anything by hand (desired count, protection), make sure the next apply / deploy
puts the service back to the code state.

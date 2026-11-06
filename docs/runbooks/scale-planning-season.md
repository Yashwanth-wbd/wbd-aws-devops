# Runbook: scale for planning season

The upfront / planning season brings many concurrent what-if simulations and optimization runs.
Scale **two weeks before**, through a PR, and scale back after the season.

## 1. Check headroom (one week earlier)

```bash
# Fargate vCPU quota (On-Demand and Spot) vs. the planned maximum
aws service-quotas get-service-quota --service-code fargate --quota-code L-3032A538   # On-Demand vCPU
aws service-quotas get-service-quota --service-code fargate --quota-code L-36FBB829   # Spot vCPU
# Last season's peaks
aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=$P-ecs Name=ServiceName,Value=$P-api \
  --start-time <season start> --end-time <season end> --period 3600 --statistics Maximum
aws cloudwatch get-metric-statistics --namespace AWS/States --metric-name ExecutionsFailed \
  --dimensions Name=StateMachineArn,Value=$OPTIMIZATION_STATE_MACHINE_ARN \
  --start-time <season start> --end-time <season end> --period 3600 --statistics Sum
# Concurrent runs and dropped requests (run queue)
aws cloudwatch get-metric-statistics --namespace MMM/Optimization --metric-name RunningRuns \
  --dimensions Name=StateMachine,Value=$P-optimization \
  --start-time <season start> --end-time <season end> --period 3600 --statistics Maximum
aws cloudwatch get-metric-statistics --namespace MMM/Optimization --metric-name ExpiredRunRequests \
  --dimensions Name=StateMachine,Value=$P-optimization \
  --start-time <season start> --end-time <season end> --period 3600 --statistics Sum
```

Needed vCPU at peak ≈ `api_max × 1 + ui_max × 0.25` (Fargate sizes in `ecs.tf`). SageMaker
Processing uses `optimizer_instance_type` (not ECS): at most `max_concurrent_runs` jobs run at once,
so the SageMaker Processing instance quota for that type must be at least `max_concurrent_runs`.
Ask for Fargate and SageMaker quota increases if headroom is below 20 % (takes days).

## 2. Raise the limits (PR)

| What | Where | Example change for prod |
|---|---|---|
| API / UI task counts | `infra/environments/dev/ecs.tf` → `ecs_sizing` (edit dev, sync) | `api_max` 10 → 16, `ui_max` 6 → 8 |
| Concurrent optimization runs | `max_concurrent_runs` in env tfvars (SSM parameter, the dispatcher reads it on every batch) | prod 50 → 80 (SageMaker quota first) |
| Queue wait before a request is dropped | `max_queue_wait_minutes` (5–50) | 30 → 45 |
| RDS instance | `rds_instance_class` / `rds_max_allocated_storage` in env tfvars | prod `db.r6g.xlarge` → `db.r6g.2xlarge` (WBD approval; applied in the maintenance window or with a Multi-AZ failover, about 1–2 min of errors) |
| Optimizer Processing | `optimizer_instance_type` in tfvars | `ml.m5.xlarge` → `ml.m5.2xlarge` |
| Training (data platform) | `training_instance_type` | one size up |
| GenAI | `genai_reserved_concurrency` in tfvars | raise if token alarms fire |
| External LLM quotas | `genai_token_quotas` | per-BU increase with WBD |

`ecs_sizing` is shared code – change only the `prod` (and `staging`, for load test) map entries.
Apply, then load-test staging with the new limits.

## 3. During the season

- Watch `whatif-p95`, `rds-cpu`, `rds-connections`, `api-5xx-rate`, `mmm-<env>-optimization-failed`,
  `runs-oldest-request`, `runs-expired-requests`.
- `max_concurrent_runs` can be raised the same day through a PR; the dispatcher uses the new value
  within a minute of the apply.
- Do not change autoscaling targets by hand without a same-day PR (nightly drift will flag drift).

## 4. After the season

Revert the PR (keep anything metrics show is still needed). Lowering `max_concurrent_runs` is
immediate (running executions finish). A smaller `rds_instance_class` needs the same short outage
as scaling up; RDS storage cannot shrink, so `rds_max_allocated_storage` only stops further growth.

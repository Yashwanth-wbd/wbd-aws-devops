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
```

Needed vCPU at peak ≈ `api_max × 1 + ui_max × 0.25` (Fargate sizes in `ecs.tf`). SageMaker
Processing uses `optimizer_instance_type` (not ECS). Ask for Fargate and SageMaker quota increases
if headroom is below 20 % (takes days).

## 2. Raise the limits (PR)

| What | Where | Example change for prod |
|---|---|---|
| API / UI task counts | `infra/environments/dev/ecs.tf` → `ecs_sizing` (edit dev, sync) | `api_max` 10 → 16, `ui_max` 6 → 8 |
| Aurora ACU | `aurora_min_acu` / `aurora_max_acu` in env tfvars | prod max 32 → 48 (WBD approval) |
| Optimizer Processing | `optimizer_instance_type` in tfvars | `ml.m5.xlarge` → `ml.m5.2xlarge` |
| Training (data platform) | `training_instance_type` | one size up |
| GenAI | `genai_reserved_concurrency` in tfvars | raise if token alarms fire |
| External LLM quotas | `genai_token_quotas` | per-BU increase with WBD |

`ecs_sizing` is shared code – change only the `prod` (and `staging`, for load test) map entries.
Apply, then load-test staging with the new limits.

## 3. During the season

- Watch `whatif-p95`, `aurora-cpu`, `aurora-acu-max`, `api-5xx-rate`, `mmm-<env>-optimization-failed`.
- Do not change autoscaling targets by hand without a same-day PR (nightly drift will flag drift).

## 4. After the season

Revert the PR (keep anything metrics show is still needed). Lowering `aurora_max_acu` is online;
document any Aurora scale-in delay in the change ticket.

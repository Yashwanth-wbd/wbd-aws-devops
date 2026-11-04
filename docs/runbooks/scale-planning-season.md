# Runbook: scale for planning season

The upfront / planning season brings many concurrent what-if simulations and optimizer runs.
Scale **two weeks before**, through a PR, and scale back after the season.

## 1. Check headroom (one week earlier)

```bash
# Fargate vCPU quota (On-Demand and Spot) vs. the planned maximum
aws service-quotas get-service-quota --service-code fargate --quota-code L-3032A538   # On-Demand vCPU
aws service-quotas get-service-quota --service-code fargate --quota-code L-36FBB829   # Spot vCPU
# Last season's peaks
aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=$P-ecs Name=ServiceName,Value=$P-optimizer-worker \
  --start-time <season start> --end-time <season end> --period 3600 --statistics Maximum
```

Needed vCPU at peak ≈ api_max × 0.5 + whatif_max × 1 + optimizer_max × 2 (+ genai max × 0.5).
Ask for a quota increase if that is above 80 % of the quota (takes days).

## 2. Raise the limits (PR)

| What | Where | Example change for prod |
|---|---|---|
| API / worker task counts | `infra/environments/dev/ecs.tf` → `ecs_sizing` (edit dev, sync) | api_max 10 → 16, whatif_min 2 → 4, whatif_max 6 → 12, optimizer_max 10 → 20 |
| GenAI gateway | `genai.tf` → `genai_sizing` | max 6 → 10 |
| Database | `rds_instance_class` in `prod/terraform.tfvars` | one size up (Multi-AZ: the standby is changed first, about 1 min failover) |
| Cache | `redis_node_type` in tfvars | one size up (online, replicas first) |
| Bedrock | Bedrock service quotas (tokens / requests per minute) | request increase; raise `genai_token_quotas` if WBD agrees |

`ecs_sizing` is shared code, so the PR changes all environments' maps at once – change only the
`prod` (and `staging`, for the load test) entries. Apply, then load-test staging with the new limits.

## 3. During the season

- Watch `queue-oldest-job`, `whatif-p95`, `rds-cpu`, `api-5xx-rate`, and the
  `mmm-prd-optimizer-worker-backlog-high` alarm.
- Do not change the autoscaling targets by hand: the next apply and the nightly drift check would
  revert / flag it. If you must (SEV2), use `aws application-autoscaling register-scalable-target
  --service-namespace ecs --resource-id service/$P-ecs/$P-optimizer-worker --scalable-dimension
  ecs:service:DesiredCount --max-capacity 30` and follow up with the PR the same day.

## 4. After the season

Revert the PR (keep anything the metrics show is still needed). Database downsizing is a
change-ticket item (short failover).

# Runbook: model drift

The model-monitor state machine `mmm-<env>-model-monitor` runs per business unit (schedule
`mmm-<env_short>-drift-<bu>` when `enable_model_monitor_schedule = true`, or by hand). It exports
recent features from Databricks, runs the training image with argument `drift` against
`s3://<models>/baseline/<bu>/` (published on approval), and puts metric `MMM/Models` `ModelDrift`
(dimensions `BusinessUnit`, `Check=overall`). Use this runbook when:

* `mmm-<env>-model-drift-<bu>` is in ALARM (score above the threshold), or
* `mmm-<env>-model-monitor-failed` fires (the check itself failed).

Drift does not stop anything: planners keep using the approved model until a new one is approved.

## 1. Drift above the threshold

```bash
aws stepfunctions list-executions --state-machine-arn <data_platform.monitor_state_machine> --max-results 5 \
  --query 'executions[].[name,status,startDate]'
aws s3 cp s3://<models>/monitoring/<bu>/<yyyy-mm-dd>/drift.json -    # {"score": ..., "checks": {...}}
```

1. Share `drift.json` (which checks moved) with the data science owner of that business unit.
2. Decide together:
   * **Real change in the data** (new channel, season): request a refresh
     (`scripts/trigger-model-refresh.sh <env> <bu> "drift <score>"`); the new version goes
     through thresholds and approval as usual.
   * **Expected / temporary** (holiday peak): accept, note it in the ticket. If it repeats, raise
     `business_units.<bu>.drift.threshold` in `data/model-thresholds.yaml` (PR, applied by
     `terraform.yml`).
   * **Data problem upstream**: hand over to the data engineers; do not retrain on bad data.
3. With `auto_refresh_on_drift = true` the state machine has already sent the refresh request
   (state **RequestRefresh**); check `mmm-<env>-model-refresh` for the new execution.

## 2. Drift check failed

| Failing state | Likely cause | Fix |
|---|---|---|
| `StartDatabricksExport` / `ExportFailed` | Databricks job id, connection secret, or the job does not support `purpose = monitor` | As in [model-refresh-failed.md](model-refresh-failed.md); data team adds the monitor mode |
| `CheckDrift` | `models/baseline/<bu>/` empty (no approved version with a baseline yet), image without the `drift` entrypoint, no features in `lakehouse/monitoring/<bu>/<date>/` | Approve a version that has `baseline/` ([model-rollback.md](model-rollback.md) shows the promote flow); training team adds the entrypoint; keep the schedule off meanwhile (`enable_model_monitor_schedule = false`) |
| `ReadDrift` | `drift.json` missing or not JSON | Training team fixes the output (contract in [data/README.md](../../data/README.md)) |
| `PublishDrift` | `score` missing or not a number | Same |

Re-run by hand after the fix:

```bash
aws stepfunctions start-execution --state-machine-arn <data_platform.monitor_state_machine> \
  --input '{"business_unit":"<bu>"}'
```

## 3. After

Record the score, the decision and who made it in the ticket. Threshold changes go through a PR
on `data/model-thresholds.yaml`.

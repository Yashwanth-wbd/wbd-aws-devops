# Runbook: Databricks write-back failed

After **RegisterModel**, the model-refresh state machine starts the Databricks write-back job
(`databricks_writeback_job_id`) with `business_unit`, `refresh_id`, `results_uri`
(`s3://<models>/evaluation/<bu>/<refresh_id>/`) and `model_package_arn`. The job writes
`predictions/` and `lift/` to the Gold monitoring tables. When it fails, the execution ends in
**WritebackFailed** and `mmm-<env>-model-refresh-failed` fires.

What still works: the model package is registered (`PendingManualApproval`) and governance can
evaluate and approve it; the optimizer keeps the last approved curves. What is missing: the Gold
tables do not have this refresh's predictions and lift (Databricks dashboards show the previous
refresh).

## 1. Find the run

```bash
aws stepfunctions get-execution-history --execution-arn <arn> --reverse-order --max-results 20 \
  --query 'events[?type==`TaskSucceeded` || type==`TaskFailed`].[timestamp,type]'
# the Databricks run id is in the output of StartDatabricksWriteback (writeback.run_id)
aws stepfunctions get-execution-history --execution-arn <arn> \
  --query 'events[?stateExitedEventDetails.name==`StartDatabricksWriteback`].stateExitedEventDetails.output'
```

Open that run in the Databricks workspace (Jobs → run id).

## 2. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| `States.Http.StatusCode.400/404` on StartDatabricksWriteback | `databricks_writeback_job_id` is `0` or the job was deleted | Data team deploys the job (`databricks.yml`); set the id in tfvars (PR) |
| `States.Http.StatusCode.401/403` | Databricks service principal secret rotated / expired | Update the EventBridge connection ([rotation.md](rotation.md#databricks-connection-model-refresh)) |
| Databricks run `FAILED`: path not found | Evaluation output has no `predictions/` or `lift/` | Training team fixes the `evaluate` step (contract in [data/README.md](../../data/README.md)) |
| Databricks run `FAILED`: access denied on S3 | Unity Catalog storage credential / external location for the `models` bucket `evaluation/` prefix missing | WBD Databricks admins add the external location (read only) |
| Databricks run `FAILED`: table / schema errors | Job logic | Data engineers, with the Databricks run URL |

## 3. Re-run only the write-back

The registered package does not need a new refresh. After the fix, the data team re-runs the
Databricks job with the same parameters (from the execution history: `business_unit`,
`refresh_id`, `results_uri`, `model_package_arn`) from the Databricks UI or CLI:

```bash
databricks jobs run-now <databricks_writeback_job_id> --json '{"job_parameters":{"business_unit":"<bu>","refresh_id":"<refresh_id>","results_uri":"s3://<models>/evaluation/<bu>/<refresh_id>/","model_package_arn":"<arn>"}}'
```

A full refresh ([model-refresh-failed.md](model-refresh-failed.md) §4) also works but trains and
registers a new version.

## 4. After

Record the execution ARN, the Databricks run and the cause in the ticket. The failed execution
stays in the history; the `model-refresh-failed` alarm returns to OK on its own.

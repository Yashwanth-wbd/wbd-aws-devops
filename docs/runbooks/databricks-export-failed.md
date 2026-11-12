# Runbook: Databricks export failed

The first step of a model refresh (and of the drift check) starts the WBD Databricks export job of
the business unit through the export Lambda `mmm-<env_short>-databricks-export` and polls it every
minute. The job writes raw Parquet to `s3://<landing>/raw/databricks/<bu>/<refresh_id>/` (drift
check: `monitor-<monitor_id>/`) through the write-only Unity Catalog role. When it fails, the
execution ends in **ExportFailed** (or a `DatabricksExportError` on StartExport / GetExportStatus),
`mmm-<env>-model-refresh-failed` (or `-model-monitor-failed`) fires, and repeated Lambda errors
also fire `mmm-<env_short>-databricks-export-errors`.

Nothing downstream ran: no Glue job, no training, no new model. Planners keep the last approved model.

## 1. Find the run

```bash
aws stepfunctions get-execution-history --execution-arn <arn> --reverse-order --max-results 30 \
  --query 'events[?type==`TaskFailed` || type==`LambdaFunctionFailed` || type==`ExecutionFailed`]'
# Databricks run id and final state
aws stepfunctions get-execution-history --execution-arn <arn> \
  --query 'events[?stateExitedEventDetails.name==`GetExportStatus`].stateExitedEventDetails.output' | tail -n 3
aws logs tail /aws/lambda/mmm-<env_short>-databricks-export --since 6h
```

Open the run in the Databricks workspace (Jobs → run id) or give the run id to WBD Databricks.

## 2. Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| `DatabricksExportError: no export job id for <bu>` | `databricks_export_job_ids` has no entry for the BU (SSM `databricks/export_job_ids`) | WBD gives the job ID; PR to `terraform.tfvars`, apply |
| HTTP 401 / 403 on the token or `run-now` | Service principal secret rotated / expired, or the SP lost "Can manage run" on the job | Update `mmm/<env>/databricks/export-sp` `{"client_id","client_secret"}` ([rotation.md](rotation.md)); WBD grants the permission |
| HTTP 400 / 404 on `run-now` | Job deleted or job parameters renamed | WBD redeploys the job with the parameters `business_unit`, `output_uri`, `purpose`, `request_id` |
| Lambda timeout / connection error | No route to the workspace: NAT down, PrivateLink endpoint not accepted, IP access list blocks `nat_public_ips` | `terraform output nat_public_ips`; check the endpoint state; WBD Databricks admins check the access list |
| Run `FAILED`: access denied on S3 | Unity Catalog storage credential / external location for `raw/databricks/` missing or not validated | Phase 2 of the UC role ([databricks-access](../../infra/modules/databricks-access/README.md)); WBD validates the credential |
| Run `FAILED`: KMS access denied | The export did not use the BU key (landing bucket policy requires it under `raw/databricks/<bu>/`) | WBD sets the BU key on the external location / write options |
| Run `FAILED`: source table errors | Upstream data in the WBD catalog | WBD data owners, with the run URL |

## 3. Re-run

After the fix, start a new refresh (a new `refresh_id`, so a new export folder):

```bash
scripts/trigger-model-refresh.sh <env> <business_unit>
```

The partial export folder of the failed run can stay (lifecycle on the landing bucket); Glue only
reads the folder of its own `refresh_id`.

## 4. After

Record the execution ARN, the Databricks run id and the cause in the ticket.

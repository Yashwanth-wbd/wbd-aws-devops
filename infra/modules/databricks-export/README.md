# databricks-export

The **Databricks export Lambda** (v4): the model-refresh and model-monitor state machines use it to
start the WBD-owned Databricks export job of a business unit and to poll it until it is done.
Databricks is only the source catalog; the export job writes raw Parquet to
`landing/raw/databricks/<bu>/<refresh_id>/` through the write-only Unity Catalog role
(`databricks-access` module), and Glue takes over from there.

**Status:** implemented (v4 architecture).

## Flow

```
state machine  --invoke {action: start}-->  <prefix>-databricks-export (Lambda, VPC)
                                                |  OAuth M2M token: POST <host>/oidc/v1/token (client credentials)
                                                |  job id: SSM databricks/export_job_ids [<bu>]
                                                v
                                           POST /api/2.2/jobs/run-now  (job_parameters, idempotency_token)
state machine  Wait 60 s -> invoke {action: status} -> GET /api/2.2/jobs/runs/get
                                                |  on success: writes <output_uri>_manifest.json (BU key)
                                                v
                                           {done, succeeded, life_cycle_state, result_state, message}
```

## Event contract

| Action | Input | Output |
|---|---|---|
| `start` | `business_unit`, `output_uri` (`s3://<landing>/raw/databricks/<bu>/<id>/`), `purpose` (`refresh` / `monitor`), `request_id` (idempotency token) | `{run_id}` |
| `status` | `run_id`, `business_unit`, `output_uri` | `{done, succeeded, life_cycle_state, result_state, message}` |

The export job receives the job parameters `business_unit`, `output_uri`, `purpose` and
`request_id`. HTTP 429, 5xx and network errors raise `DatabricksRetryable` (the state machine
retries them); anything else raises `DatabricksExportError` and fails the execution
(runbook `databricks-export-failed`).

## What it creates

| Resource | Name | Notes |
|---|---|---|
| Lambda | `<prefix>-databricks-export` | Python 3.12, code in `lambda/handler.py` (shipped by Terraform), VPC, X-Ray |
| IAM role | `<prefix>-databricks-export-lambda` | Read the service-principal secret and the job-ID parameter, put `_manifest.json` under `manifest_prefix`, BU keys, ENI, X-Ray |
| Log group | `/aws/lambda/<prefix>-databricks-export` | `logs` key |
| Alarm | `<prefix>-databricks-export-errors` | Errors in 2 of 3 five-minute periods |

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix`, `databricks_host` | – | Workspace URL (https) |
| `service_principal_secret_arn` | – | `mmm/<env>/databricks/export-sp` = `{"client_id", "client_secret"}` (filled out-of-band) |
| `job_ids_parameter_name`, `job_ids_parameter_arn` | – | SSM `databricks/export_job_ids` = `{"<bu>": <job id>}` |
| `landing_bucket_arn`, `manifest_prefix` | `raw/databricks/` | |
| `business_unit_keys`, `default_key_arn` | – | Manifest encryption (landing bucket policy requires the BU key) |
| `secrets_kms_key_arn`, `logs_kms_key_arn`, `log_retention_days` | `30` days | |
| `timeout` | `60` | Seconds |
| `subnet_ids`, `security_group_ids` | – | Private-app subnets, `databricks_export` security group (443 out: NAT or PrivateLink) |
| `alarm_topic_arn`, `permissions_boundary_arn`, `tags` | – | |

## Outputs

`function_name`, `function_arn`, `log_group_name`, `alarm_name`.

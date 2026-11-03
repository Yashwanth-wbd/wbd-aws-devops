# mwaa

Amazon MWAA (managed Airflow) environment `mmm-<env>-airflow` that orchestrates data loading,
data quality and retraining on Databricks.

**Status:** implemented in Step 13 (created only when `enable_data_platform = true`).

## What it creates

| Resource | Notes |
|---|---|
| `aws_mwaa_environment` | Private web UI (`PRIVATE_ONLY`), two private-app subnets, the `mwaa` security group, customer-managed key `mwaa`, all five log types on. Takes 20–30 minutes to create |
| IAM role `mmm-<env>-mwaa-exec` | Trusts `airflow.amazonaws.com` / `airflow-env.amazonaws.com` (this account only). Has the permission boundary |
| Alarm `mmm-<env>-airflow-scheduler-heartbeat` | No scheduler heartbeat for 15 min → alert topic |

The DAG bucket (`wbd-mmm-<env>-mwaa-<region>`) is made by the stack with the `s3-bucket` module,
so it gets the same hardening as the other buckets.

## Execution role permissions

| What | Why |
|---|---|
| Read the MWAA bucket | DAGs and `requirements.txt` |
| `logs:*` on `airflow-mmm-<env>-airflow-*`, `cloudwatch:PutMetricData`, `airflow:PublishMetrics` | Airflow logs and metrics |
| SQS `airflow-celery-*` + key `mwaa` (only via SQS/S3) | The Celery queue MWAA manages |
| `secretsmanager:GetSecretValue` on `mmm/<env>/airflow/*` | Airflow connections (e.g. `databricks_default`) |
| Read/write `data_bucket_arns` + `data_kms_key_arns` | Tasks read landing and write run manifests / data-quality results |

## Airflow configuration

| Option | Value |
|---|---|
| `secrets.backend` | Secrets Manager. Connection `<id>` = secret `mmm/<env>/airflow/connections/<id>` |
| `core.dags_are_paused_at_creation` | `False` so a new DAG runs on its first trigger |
| `core.load_examples`, `webserver.expose_config` | `False` |
| `mmm.<key>` | From `dag_settings` (bucket names, business units). DAGs read them with `conf.get("mmm", "<key>")` |

`requirements.txt` is **not** managed by Terraform. `data.yml` uploads it and calls
`update-environment` with the new object version. The lifecycle block ignores those fields.

## Inputs

| Name | Type | Default |
|---|---|---|
| `name_prefix` | string | – |
| `airflow_version` | string | `2.10.3` |
| `environment_class` / `min_workers` / `max_workers` / `schedulers` | string / number | `mw1.small` / 1 / 2 / 2 |
| `source_bucket_arn` | string | – |
| `subnet_ids` (first two used), `security_group_id` | list / string | – |
| `kms_key_arn` | string | – (`module.kms.key_arns["mwaa"]`) |
| `secrets_prefix`, `secrets_kms_key_arn` | string | – |
| `data_bucket_arns`, `data_kms_key_arns` | list(string) | `[]` / – |
| `dag_settings` | map(string) | `{}` |
| `log_level` | string | `WARNING` |
| `weekly_maintenance_window_start` | string | `SUN:03:00` |
| `alarm_topic_arn`, `permissions_boundary_arn` | string | – |

## Outputs

`environment_name`, `environment_arn`, `webserver_url`, `execution_role_arn`,
`airflow_user_role_arn` (for `airflow:InvokeRestApi`), `log_group_names` (scheduler, task, worker).

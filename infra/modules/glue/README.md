# glue

The **AWS Glue lakehouse** of the model refresh (v4): Glue Data Catalog databases, the six Spark
jobs of the medallion and the exports, the Silver Data Quality ruleset, and the job role. The
model-refresh and model-monitor state machines (environment `data.tf`) run the jobs with
`glue:startJobRun.sync`, one business unit per execution.

**Status:** implemented (v4 architecture). Job code belongs to the data engineers
(`data/glue/jobs/<job>.py`, uploaded by `.github/workflows/glue.yml`); DevOps owns this plumbing.

## Flow

```
landing  raw/databricks/<bu>/<refresh_id>/  (Parquet from the WBD Databricks export job)
   |  bronze           ingest as is + load metadata (job bookmark on)
   v
lakehouse bronze/  ->  silver   cleanse, conform, Data Quality ruleset <prefix>-silver (fails the refresh)
                   ->  gold     per-BU modeling tables (adstock, saturation)
                          |-- export-training  -> training-data  immutable Parquet snapshot + metadata
                          |-- export-rds       -> RDS PostgreSQL reference tables (JDBC via RDS Proxy, IAM token as mmm_etl)
                          '-- export-monitor   -> lakehouse monitoring/<bu>/<monitor_id>/ (drift check)
```

## What it creates

| Resource | Name | Notes |
|---|---|---|
| Catalog databases | `<prefix_>_bronze`, `_silver`, `_gold` (hyphens → `_`) | Location `s3://<lakehouse>/<layer>/` |
| Catalog encryption (optional) | account / region setting | `manage_catalog_encryption`: metadata and connection passwords with the `s3` key |
| Security configuration | `<prefix>-glue` | S3 SSE-KMS (`s3` key), CloudWatch logs SSE-KMS (`logs` key), job bookmarks CSE-KMS |
| Log group | `/aws-glue/jobs/<prefix>` | Continuous logging of every job, `logs` key |
| Connection | `<prefix>-glue-vpc` | Type NETWORK: job ENIs in one private-app subnet with `glue` + `data_clients` security groups |
| Data Quality ruleset | `<prefix>-silver` | `silver_ruleset` (DQDL), default `Rules = [ RowCount > 0 ]` |
| IAM role | `<prefix>-glue` | Permission boundary; see below |
| Seed scripts | `s3://<glue-assets>/scripts/<job>.py` | Raise `SystemExit` until `glue.yml` uploads the real code (`ignore_changes` on content) |
| Jobs | `<prefix>-glue-{bronze,silver,gold,export-training,export-rds,export-monitor}` | `glueetl`, Delta Lake, metrics, continuous logs, `max_concurrent_runs` = number of business units |

Job arguments set here: `--datalake-formats delta`, the Delta Spark settings, `--ENV`, the bucket
and database names, `--TempDir s3://<glue-assets>/temp/<job>/`, `--job-bookmark-option`
(enabled for bronze), `--DQ_RULESET` (silver) and `--DB_HOST/PORT/NAME/USER` (export-rds). The
state machine adds the per-run values `--business_unit`, `--run_id`, `--purpose` (`refresh` |
`monitor`) and `--raw_uri` / `--snapshot_uri` / `--monitor_uri`.

## Role permissions

| Statement | Scope |
|---|---|
| Scripts and temp | `glue-assets` `scripts/*` read, `temp/*` read / write |
| Raw extract | `landing` `raw/*` read only |
| Lakehouse | read / write (Delta tables, `monitoring/`) |
| Training snapshot | `training-data` put / get (Object Lock keeps it immutable) |
| KMS | data keys (`s3` + per-BU) and the `logs` key |
| Glue | catalog actions on the three databases and their tables, the connection, the DQ ruleset |
| CloudWatch | `PutMetricData` in namespaces `Glue` and `AWS/Glue/DataQuality` |
| EC2 | describe calls, create / delete / tag the job ENIs |
| RDS | `rds-db:connect` as `db_user` (`mmm_etl`) on the proxy |

## Inputs

| Name | Default | Description |
|---|---|---|
| `name_prefix`, `environment`, `business_units` | – | |
| `assets_bucket_name`, `landing_bucket_name`, `lakehouse_bucket_name`, `training_data_bucket_name` | – | Buckets from the environment's `module.buckets` |
| `data_kms_key_arns`, `s3_kms_key_arn`, `logs_kms_key_arn` | – | kms module |
| `log_retention_days` | `30` | |
| `glue_version` | `5.0` | Spark 3.5, Python 3.11 |
| `worker_type`, `number_of_workers`, `timeout_minutes` | `G.1X`, `2`, `120` | |
| `extra_job_arguments` | `{}` | Extra `--key` arguments per job key |
| `subnet_id`, `availability_zone`, `security_group_ids` | – | Private-app subnet, its AZ, `glue` + `data_clients` |
| `db_host`, `db_name`, `db_user`, `db_user_arn` | `db_user = mmm_etl` | RDS Proxy |
| `silver_ruleset` | `Rules = [ RowCount > 0 ]` | DQDL (environment reads `data/glue/dq/silver.dqdl` when it exists) |
| `manage_catalog_encryption` | `true` | `false` if WBD already sets it for the account |
| `permissions_boundary_arn`, `tags` | – | |

## Outputs

`role_arn`, `job_names` (map job key → name), `job_arns`, `database_names`, `connection_name`,
`ruleset_name`, `log_group_name`, `security_configuration`.

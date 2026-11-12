# data/ – Glue job scripts, Data Quality rules and model thresholds (Step 13, v4)

The data engineers own the Glue job code and the WBD Databricks export job; DevOps owns how they
are shipped, run and governed. Full guide: [docs/10](../docs/10-data-platform-and-model-governance.md).

| Path | What | Used by |
|---|---|---|
| `glue/jobs/<job>.py` (added by the data engineers) | PySpark scripts of the Glue jobs `bronze`, `silver`, `gold`, `export-training`, `export-rds`, `export-monitor` (file name = job key) | `.github/workflows/glue.yml`: `main` → dev, manual → staging / prod (approval); uploaded to `s3://<glue-assets>/scripts/<job>.py` |
| `glue/dq/silver.dqdl` (optional) | Glue Data Quality ruleset (DQDL) the Silver job evaluates; a failing rule fails the refresh | Terraform (`data.tf` reads it into the ruleset `<prefix>-silver`; default `Rules = [ RowCount > 0 ]`) |
| `model-thresholds.yaml` | Acceptance thresholds per business unit for models in the SageMaker Model Registry, the baseline location and the drift threshold per business unit | `model-governance.yml` (`scripts/model_governance.py`) and Terraform (`data.tf` reads the drift thresholds, so `terraform.yml` runs on changes) |

The Databricks export job itself lives in the WBD Databricks workspace (owned and deployed by
WBD); this repo only stores its job ID per business unit (`databricks_export_job_ids` → SSM
`/mmm/<env>/databricks/export_job_ids`).

## Contract with the model-refresh pipeline

```
Databricks export -> Glue Bronze -> Silver (DQ) -> Gold -> [export-training || export-rds]
  -> SageMaker train -> evaluate -> register (PendingManualApproval) -> results publisher (model_results)
```

* **Databricks export job** (WBD) receives the job parameters `business_unit`, `output_uri`
  (`s3://<landing>/raw/databricks/<bu>/<refresh_id>/`), `purpose` (`refresh`) and `request_id`,
  and writes raw Parquet there through the write-only Unity Catalog role. On success the export
  Lambda adds `_manifest.json` (run ID, state, time) next to it.
* **Every Glue job** receives `--business_unit`, `--run_id` (= `refresh_id`), `--purpose`, and from
  Terraform `--ENV`, `--LANDING_BUCKET`, `--LAKEHOUSE_BUCKET`, `--TRAINING_DATA_BUCKET`, the database
  names and `--TempDir`. Tables are Delta Lake under `s3://<lakehouse>/<layer>/`, catalogued in
  `<prefix_>_bronze` / `_silver` / `_gold`.
  * `bronze` also gets `--raw_uri` (the export folder above); job bookmarks are on.
  * `silver` evaluates `--DQ_RULESET` (`<prefix>-silver`) and must fail the run when it fails.
  * `export-training` gets `--snapshot_uri` (`s3://<training-data>/<bu>/<refresh_id>/`) and writes
    the immutable Parquet snapshot + metadata (Object Lock).
  * `export-rds` gets `--DB_HOST/PORT/NAME/USER` (`mmm_etl` through RDS Proxy; the password is an
    IAM token from `generate_db_auth_token`) and writes only the reference tables the app
    migrations granted to `mmm_etl`.
* **Training image** writes the model artifact; the evaluation step (argument `evaluate`) writes under
  `s3://<models>/evaluation/<bu>/<refresh_id>/`:
  * `evaluation.json` – a flat `{"metric": value}` object with every metric in `model-thresholds.yaml`
  * `curves/` – response curves (published to `curves/<bu>/` on approval)
  * `baseline/` – the reference statistics for the drift check (published to `baseline/<bu>/` on approval)
  * `predictions/`, `lift/` – read by the results publisher
* **Results publisher** is invoked with
  `{"event": "model_results", "business_unit", "refresh_id", "model_package_arn", "evaluation_uri"}`
  and writes predictions, lift and the evaluation results to RDS (tagged with the model package; the
  approval status stays in the registry).
* A missing metric fails the check. Thresholds are placeholders until WBD and EY sign them off.

## Contract with the model-monitor (drift) pipeline

* The same export runs with `purpose = monitor` into `raw/databricks/<bu>/monitor-<monitor_id>/`,
  then Bronze → Silver → Gold with `--purpose monitor`.
* `export-monitor` gets `--monitor_uri` (`s3://<lakehouse>/monitoring/<bu>/<date>/`) and writes only
  the latest features there.
* The training image runs with the argument `drift`, inputs `/opt/ml/processing/baseline`,
  `/opt/ml/processing/curves`, `/opt/ml/processing/features`, and writes `drift.json`
  (`{"score": 0-1, "checks": {...}}`) to `s3://<models>/monitoring/<bu>/<date>/`.
* A score above `business_units.<bu>.drift.threshold` raises the alarm and, with
  `auto_refresh_on_drift = true`, requests a model refresh.

## Contract with the optimization run (app teams)

* The browser uploads the run input with a presigned PUT (signed by the API) to
  `s3://<uploads>/<bu>/runs/<run_id>/input/`; the API then queues `{run_id, business_unit,
  run_type, input_s3_uri, requested_by, dry_run}` (`run_type` = `optimize` | `forecast`).
* The optimizer ECS task gets `RUN_ID`, `BUSINESS_UNIT`, `RUN_TYPE`, `INPUT_S3_URI`,
  `OUTPUT_S3_URI` (`s3://<results>/runs/<run_id>/output/`), `CURVES_S3_URI`
  (`s3://<models>/curves/<bu>/`) and `DRY_RUN`, and exits non-zero on failure.

## Check locally

```bash
pip install -r scripts/requirements-model-governance.txt
python scripts/model_governance.py check-thresholds
python scripts/model_governance.py evaluate-file --business-unit streaming --metrics evaluation.json
```

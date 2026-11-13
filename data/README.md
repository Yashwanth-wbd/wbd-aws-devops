# data/ – Glue job scripts, Data Quality rules and model thresholds (Step 13, v5)

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
  -> results/data publisher (reference_data) -> SageMaker train -> evaluate
  -> register (PendingManualApproval) -> SageMaker ML Lineage -> results/data publisher (model_results)
```

* **Databricks export job** (WBD) receives the job parameters `business_unit`, `output_uri`
  (`s3://<landing>/raw/databricks/<bu>/<refresh_id>/`), `purpose` (`refresh`) and `request_id`,
  and writes raw Parquet there through the write-only Unity Catalog role. On success the export
  Lambda adds `_manifest.json` (run ID, state, time) next to it.
* **Every Glue job** receives `--business_unit`, `--run_id` (= `refresh_id`), `--purpose`,
  `--source_export_run_id` (Databricks run of this refresh), and from
  Terraform `--ENV`, `--LANDING_BUCKET`, `--LAKEHOUSE_BUCKET`, `--TRAINING_DATA_BUCKET`, the database
  names and `--TempDir`. Tables are Delta Lake under `s3://<lakehouse>/<layer>/`, catalogued in
  `<prefix_>_bronze` / `_silver` / `_gold`.
  * `bronze` also gets `--raw_uri` (the export folder above); job bookmarks are on.
  * `silver` evaluates `--DQ_RULESET` (`<prefix>-silver`) and must fail the run when it fails.
  * `export-training` gets `--snapshot_uri` (`s3://<training-data>/<bu>/<refresh_id>/`) and writes
    the immutable Parquet snapshot + metadata (Object Lock).
  * `export-rds` has **no database access**. It gets `--output_uri`
    (`s3://<lakehouse>/rds-export/<bu>/<refresh_id>/`) and `--RDS_EXPORT_PREFIX` (`rds-export/`),
    writes one Parquet folder per Gold reference table (`<table>/part-*.parquet`) and, last,
    `_manifest.json`:
    `{"business_unit", "refresh_id", "tables": [{"name", "path", "rows", "load_mode": "replace" | "upsert", "keys": [...]}]}`.
    The prefix expires after `rds_export_retention_days` (30).
  * **Lineage table properties:** after writing, every job sets these Data Catalog table parameters
    (`glue:UpdateTable`) on the Bronze / Silver / Gold / export tables it wrote: `mmm_refresh_id`
    (`--run_id`), `mmm_business_unit`, `mmm_source_export_run_id` (`--source_export_run_id`, the
    Databricks run), `mmm_source_uri` (the input folder), `mmm_upstream_tables` (comma-separated
    `<database>.<table>` read by the job; empty for Bronze), `mmm_delta_version` (the Delta table version
    this write created), `mmm_glue_run_id` (`JOB_RUN_ID`), `mmm_script_version` (the `commit` metadata
    `glue.yml` sets on the script object) and `mmm_written_at` (ISO 8601 UTC).
* **Training image** writes the model artifact; the evaluation step (argument `evaluate`) writes under
  `s3://<models>/evaluation/<bu>/<refresh_id>/`:
  * `evaluation.json` – a flat `{"metric": value}` object with every metric in `model-thresholds.yaml`
  * `curves/` – response curves (published to `curves/<bu>/` on approval)
  * `baseline/` – the reference statistics for the drift check (published to `baseline/<bu>/` on approval)
  * `predictions/`, `lift/` – read by the results/data publisher
* **Results/data publisher** (one Lambda, DB user `mmm_app` through RDS Proxy, IAM token) has two
  model-refresh events:
  * `{"event": "reference_data", "business_unit", "refresh_id", "input_uri"}` – reads
    `_manifest.json` under `input_uri` and loads each table into RDS in one transaction per table
    (replace or upsert as the manifest says), idempotent per `refresh_id`, and publishes the metric
    `ReferenceRowsPublished` (namespace `MMM/Data`, dimension `BusinessUnit`). An
    error fails the refresh before training.
  * `{"event": "model_results", "business_unit", "refresh_id", "model_package_arn", "evaluation_uri"}`
    – writes predictions, lift and the evaluation results to RDS (tagged with the model package;
    the approval status stays in the registry).
  * Timeout `publisher_timeout_seconds` (120, up to 900) and memory `publisher_memory_mb` (512).
* **SageMaker ML Lineage** (state machine, no code needed): context `<prefix>-refresh-<refresh_id>`
  (type `MMMModelRefresh`, properties BU, refresh ID, Databricks run ID, training job, model
  package) with artifacts for the raw export, the reference data and the training snapshot
  (`ContributedTo`), the training job's trial component (`<job>-aws-training-job`, `ContributedTo`)
  and the model package (`Produced`). `aws sagemaker query-lineage --start-arns <model package
  artifact> --direction Ascendants` reaches the training data and the export. A lineage failure does not fail the refresh:
  it publishes `MMM/Models` `LineageRecordFailed` and raises the alarm `lineage-record-failed-<bu>`.
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

# data/ – Databricks bundle hook and model thresholds (Step 13)

The data engineers own the Databricks code; DevOps owns how it is shipped and governed.
Full guide: [docs/10](../docs/10-data-platform-and-model-governance.md).

| Path | What | Used by |
|---|---|---|
| `databricks/` (added by the data engineers) | Databricks Asset Bundle (`databricks.yml`) with the feature / snapshot job the model-refresh and model-monitor state machines start (`databricks_refresh_job_id`) and the write-back job (`databricks_writeback_job_id`) | `.github/workflows/databricks.yml`: `main` → dev, manual → staging / prod (approval) |
| `model-thresholds.yaml` | Acceptance thresholds per business unit for models in the SageMaker Model Registry, the baseline location and the drift threshold per business unit | `model-governance.yml` (`scripts/model_governance.py`) and Terraform (`data.tf` reads the drift thresholds, so `terraform.yml` runs on changes) |

## Contract with the model-refresh pipeline

* The Databricks job receives the job parameters `business_unit` and `snapshot_uri`
  (`s3://<training-data bucket>/<bu>/<refresh_id>/`) and writes the training snapshot there.
* The training image writes the model artifact; the evaluation step writes under
  `s3://<models bucket>/evaluation/<bu>/<refresh_id>/`:
  * `evaluation.json` – a flat `{"metric": value}` object with every metric in `model-thresholds.yaml`
  * `curves/` – response curves (published to `curves/<bu>/` on approval)
  * `baseline/` – the reference statistics for the drift check (published to `baseline/<bu>/` on approval)
  * `predictions/`, `lift/` – read by the write-back job
* The write-back job receives `business_unit`, `refresh_id`, `results_uri` (the evaluation prefix
  above) and `model_package_arn`, and writes predictions and lift to the Gold tables.
* A missing metric fails the check. Thresholds are placeholders until WBD and EY sign them off.

## Contract with the model-monitor (drift) pipeline

* The same Databricks job is started with `purpose = monitor` and `snapshot_uri`
  `s3://<lakehouse bucket>/monitoring/<bu>/<date>/`: it writes only the latest features there.
* The training image runs with the argument `drift`, inputs `/opt/ml/processing/baseline`,
  `/opt/ml/processing/curves`, `/opt/ml/processing/features`, and writes `drift.json`
  (`{"score": 0-1, "checks": {...}}`) to `s3://<models bucket>/monitoring/<bu>/<date>/`.
* A score above `business_units.<bu>.drift.threshold` raises the alarm and, with
  `auto_refresh_on_drift = true`, requests a model refresh.

## Check locally

```bash
pip install -r scripts/requirements-model-governance.txt
python scripts/model_governance.py check-thresholds
python scripts/model_governance.py evaluate-file --business-unit streaming --metrics evaluation.json
```

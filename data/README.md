# data/ – Databricks bundle hook and model thresholds (Step 13)

The data engineers own the Databricks code; DevOps owns how it is shipped and governed.
Full guide: [docs/10](../docs/10-data-platform-and-model-governance.md).

| Path | What | Used by |
|---|---|---|
| `databricks/` (added by the data engineers) | Databricks Asset Bundle (`databricks.yml`) with the feature / snapshot job the model-refresh state machine starts (`databricks_refresh_job_id`) | `.github/workflows/databricks.yml`: `main` → dev, manual → staging / prod (approval) |
| `model-thresholds.yaml` | Acceptance thresholds per business unit for models in the SageMaker Model Registry | `model-governance.yml` (`scripts/model_governance.py`) |

## Contract with the model-refresh pipeline

* The Databricks job receives the job parameters `business_unit` and `snapshot_uri`
  (`s3://<training-data bucket>/<bu>/<refresh_id>/`) and writes the training snapshot there.
* The training image writes the model artifact; the evaluation step writes
  `s3://<models bucket>/evaluation/<bu>/<refresh_id>/evaluation.json` (a flat `{"metric": value}`
  object with every metric in `model-thresholds.yaml`) and the response curves under `.../curves/`.
* A missing metric fails the check. Thresholds are placeholders until WBD and EY sign them off.

## Check locally

```bash
pip install -r scripts/requirements-model-governance.txt
python scripts/model_governance.py check-thresholds
python scripts/model_governance.py evaluate-file --business-unit streaming --metrics evaluation.json
```

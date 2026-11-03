# data/ – Airflow DAGs, quality suites and model thresholds (Step 13)

`.github/workflows/data.yml` validates this folder on every PR and publishes it to MWAA:
`main` → dev, `data-vX.Y.Z-rcN` → staging, `data-vX.Y.Z` → prod. Nothing here is uploaded by
hand. Full guide: [docs/10](../docs/10-data-platform-and-model-governance.md).

| Path | What | Published to |
|---|---|---|
| `requirements.txt` | Python packages for MWAA. The first line pins the Airflow 2.10.3 / Python 3.11 constraints file | `s3://<mwaa bucket>/requirements.txt`; MWAA is updated only when the file changes (10–30 min) |
| `dags/mmm_ingest.py` | The DAG the data-trigger Lambda starts: `resolve → databricks_enabled → transform → data_quality → retrain → write_manifest` | `s3://<mwaa bucket>/dags/` |
| `dags/mmm_lib/` | Shared helpers (run manifest). `.airflowignore` keeps the scheduler from parsing it as DAGs | same |
| `schemas/run-manifest.schema.json` | JSON Schema of the lineage record written per run to `s3://<results>/run-manifests/mmm_ingest/<run_id>.json` | – (used by tests) |
| `quality/*.json` | Great Expectations suites, run by the Databricks `data-quality` job | `s3://<quality bucket>/suites/` |
| `model-thresholds.yaml` | Acceptance thresholds per business unit, used by `model-governance.yml` | – |
| `tests/` | DAG import / convention tests and manifest schema tests (run in CI with Airflow installed) | – |
| `ruff.toml` | Lint settings (`mmm_lib` is first-party) | – |

## Rules for DAGs

* No secrets, account IDs or bucket names in code. Read settings with
  `conf.get("mmm", "<key>")` (set by Terraform) and connections by ID (Secrets Manager
  `mmm/<env>/airflow/connections/<id>`).
* Every DAG has `owner`, `retries`, tags, `catchup=False`, and no import errors (enforced by
  `tests/test_dag_integrity.py`).
* Heavy work runs in Databricks jobs, not on Airflow workers.
* New packages go into `requirements.txt` and must resolve with the constraints file. CI
  installs them the same way MWAA does.

## Run the checks locally (Linux / WSL / Git Bash with Python 3.11)

```bash
af=2.10.3; py=3.11
pip install "apache-airflow==$af" -r data/requirements.txt pytest jsonschema ruff \
  -c "https://raw.githubusercontent.com/apache/airflow/constraints-$af/constraints-$py.txt"
export AIRFLOW_HOME=/tmp/airflow AIRFLOW__CORE__LOAD_EXAMPLES=False
airflow db migrate && pytest -q data/tests
ruff check --select E,F,W,B,I --ignore E501 --target-version py311 data scripts/model_governance.py
python scripts/model_governance.py check-thresholds
```

On Windows without Airflow, `pytest data/tests/test_run_manifest.py` runs on its own. The DAG
test is skipped there and runs in CI.

## Release

```bash
git tag data-v1.0.0-rc1 && git push origin data-v1.0.0-rc1   # staging (EY delivery lead approves)
git tag data-v1.0.0     && git push origin data-v1.0.0       # prod, same commit (WBD approver)
```

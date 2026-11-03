"""Run manifest (lineage record) written to s3://<results>/run-manifests/<dag_id>/<run_id>.json.

Schema: data/schemas/run-manifest.schema.json. Pure functions, so data/tests can check them
without Airflow or AWS.
"""

from __future__ import annotations

from datetime import datetime, timezone

SCHEMA_VERSION = "1.0"
TERMINAL_OK = {"success", "skipped"}


def build_manifest(
    *,
    dag_id: str,
    run_id: str,
    environment: str,
    conf: dict,
    task_states: dict[str, str],
    databricks_runs: dict[str, str] | None = None,
    quality_results_uri: str | None = None,
    started_at: datetime | None = None,
    finished_at: datetime | None = None,
) -> dict:
    finished_at = finished_at or datetime.now(timezone.utc)
    states = {k: (v or "none") for k, v in sorted(task_states.items())}
    status = "success" if all(s in TERMINAL_OK for s in states.values()) else "failed"
    if status == "success" and all(s == "skipped" for s in states.values()):
        status = "skipped"

    source = conf.get("source") or {}
    return {
        "schema_version": SCHEMA_VERSION,
        "dag_id": dag_id,
        "run_id": run_id,
        "environment": environment,
        "trigger": conf.get("trigger", "manual"),
        "business_unit": conf.get("business_unit", "all"),
        "source": {
            "bucket": source.get("bucket"),
            "key": source.get("key"),
            "etag": source.get("etag"),
        },
        "requested_by": conf.get("requested_by"),
        "started_at": (started_at or finished_at).isoformat(),
        "finished_at": finished_at.isoformat(),
        "tasks": states,
        "databricks_runs": databricks_runs or {},
        "quality_results_uri": quality_results_uri,
        "status": status,
    }


def manifest_key(dag_id: str, run_id: str) -> str:
    return f"run-manifests/{dag_id}/{run_id}.json"

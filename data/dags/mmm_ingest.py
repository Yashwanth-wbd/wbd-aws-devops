"""mmm_ingest: one run per landed file or on-demand request (started by the data-trigger Lambda).

    resolve -> databricks_enabled -> transform -> data_quality -> retrain -> write_manifest

* Databricks jobs are found by name: <name_prefix>-transform, -data-quality, -retrain. The data
  team owns those jobs (Bronze/Silver/Gold, Great Expectations, MLflow training). retrain
  registers the new model version with the alias "candidate"; model-governance.yml evaluates it.
* Until the Airflow Variable mmm_databricks_enabled is "true", the Databricks tasks are skipped,
  so the trigger -> MWAA path can be validated before Databricks is connected.
* write_manifest always runs and writes the lineage record to
  s3://<results>/run-manifests/mmm_ingest/<run_id>.json, then fails the run if any task failed.

Settings come from MWAA (conf.get("mmm", ...)), the Databricks connection from Secrets Manager
(mmm/<env>/airflow/connections/databricks_default). Nothing secret is in this file.
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta

from airflow.configuration import conf as airflow_conf
from airflow.decorators import dag, task
from airflow.exceptions import AirflowFailException
from airflow.models import Variable
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.providers.databricks.operators.databricks import DatabricksRunNowOperator

from mmm_lib.manifest import build_manifest, manifest_key


def setting(key: str, default: str = "") -> str:
    return airflow_conf.get("mmm", key, fallback=default)


ENVIRONMENT = setting("environment", "dev")
NAME_PREFIX = setting("name_prefix", "mmm-dev")
BUSINESS_UNITS = [b for b in setting("business_units", "usnetworks,streaming,theatrical").split(",") if b]
RESULTS_BUCKET = setting("results_bucket")
QUALITY_BUCKET = setting("quality_bucket")
MODEL_CATALOG = setting("model_catalog", "mmm_dev")

DATABRICKS_CONN_ID = "databricks_default"
DATABRICKS_TASKS = ["transform", "data_quality", "retrain"]

# Rendered at run time from the resolve task's output.
JOB_PARAMETERS = {
    "environment": ENVIRONMENT,
    "business_unit": "{{ ti.xcom_pull(task_ids='resolve')['business_unit'] }}",
    "source_bucket": "{{ (ti.xcom_pull(task_ids='resolve').get('source') or {}).get('bucket', '') }}",
    "source_key": "{{ (ti.xcom_pull(task_ids='resolve').get('source') or {}).get('key', '') }}",
    "airflow_run_id": "{{ run_id }}",
}


@dag(
    dag_id="mmm_ingest",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=4,
    default_args={"owner": "mmm-data", "retries": 2, "retry_delay": timedelta(minutes=5)},
    tags=["mmm", "ingest"],
    doc_md=__doc__,
)
def mmm_ingest():
    @task
    def resolve(**context) -> dict:
        conf = dict(context["dag_run"].conf or {})
        business_unit = conf.get("business_unit", "all")
        if business_unit != "all" and business_unit not in BUSINESS_UNITS:
            raise AirflowFailException(f"unknown business_unit {business_unit!r}; expected one of {BUSINESS_UNITS} or 'all'")
        conf["business_unit"] = business_unit
        conf.setdefault("trigger", "manual")
        return conf

    @task.short_circuit(ignore_downstream_trigger_rules=False)
    def databricks_enabled() -> bool:
        return Variable.get("mmm_databricks_enabled", default_var="false").lower() == "true"

    transform = DatabricksRunNowOperator(
        task_id="transform",
        databricks_conn_id=DATABRICKS_CONN_ID,
        job_name=f"{NAME_PREFIX}-transform",
        job_parameters=JOB_PARAMETERS,
    )

    data_quality = DatabricksRunNowOperator(
        task_id="data_quality",
        databricks_conn_id=DATABRICKS_CONN_ID,
        job_name=f"{NAME_PREFIX}-data-quality",
        job_parameters={
            **JOB_PARAMETERS,
            "suites_uri": f"s3://{QUALITY_BUCKET}/suites/",
            "results_uri": f"s3://{QUALITY_BUCKET}/results/{{{{ run_id }}}}/",
        },
    )

    retrain = DatabricksRunNowOperator(
        task_id="retrain",
        databricks_conn_id=DATABRICKS_CONN_ID,
        job_name=f"{NAME_PREFIX}-retrain",
        job_parameters={**JOB_PARAMETERS, "model_catalog": MODEL_CATALOG, "register_alias": "candidate"},
    )

    @task(trigger_rule="all_done", retries=0)
    def write_manifest(conf: dict, **context) -> str:
        dag_run = context["dag_run"]
        states = {ti.task_id: ti.state for ti in dag_run.get_task_instances() if ti.task_id != "write_manifest"}
        databricks_runs = {
            t: url for t in DATABRICKS_TASKS if (url := context["ti"].xcom_pull(task_ids=t, key="run_page_url"))
        }
        manifest = build_manifest(
            dag_id=dag_run.dag_id,
            run_id=dag_run.run_id,
            environment=ENVIRONMENT,
            conf=conf,
            task_states=states,
            databricks_runs=databricks_runs,
            quality_results_uri=f"s3://{QUALITY_BUCKET}/results/{dag_run.run_id}/" if QUALITY_BUCKET else None,
            started_at=dag_run.start_date,
        )
        if RESULTS_BUCKET:
            S3Hook().load_string(
                json.dumps(manifest, indent=2),
                key=manifest_key(dag_run.dag_id, dag_run.run_id),
                bucket_name=RESULTS_BUCKET,
                replace=True,
            )
        if manifest["status"] == "failed":
            raise AirflowFailException(f"run failed: {manifest['tasks']}")
        return manifest["status"]

    conf = resolve()
    manifest = write_manifest(conf)
    conf >> databricks_enabled() >> transform >> data_quality >> retrain >> manifest


mmm_ingest()

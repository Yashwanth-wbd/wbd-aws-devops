"""DAG import and convention checks (data.yml validate job; needs Airflow + data/requirements.txt)."""

import pathlib
import sys

import pytest

DAGS = pathlib.Path(__file__).resolve().parents[1] / "dags"
sys.path.insert(0, str(DAGS))

pytest.importorskip("airflow")
from airflow.models import DagBag  # noqa: E402


@pytest.fixture(scope="session")
def dagbag():
    return DagBag(dag_folder=str(DAGS), include_examples=False)


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}


def test_every_dag_follows_conventions(dagbag):
    assert dagbag.dags, "no DAGs found"
    for dag_id, dag in dagbag.dags.items():
        assert dag.tags, f"{dag_id}: add tags"
        assert dag.default_args.get("owner"), f"{dag_id}: set default_args.owner"
        assert dag.default_args.get("retries", 0) >= 1, f"{dag_id}: set default_args.retries"
        assert dag.catchup is False, f"{dag_id}: catchup must be False"


def test_ingest_dag_shape(dagbag):
    dag = dagbag.get_dag("mmm_ingest")
    assert dag is not None
    assert dag.timetable.summary == "None", "mmm_ingest is started only by the data trigger"
    assert set(dag.task_ids) == {"resolve", "databricks_enabled", "transform", "data_quality", "retrain", "write_manifest"}
    assert dag.get_task("write_manifest").trigger_rule == "all_done"
    assert dag.get_task("transform").upstream_task_ids == {"databricks_enabled"}

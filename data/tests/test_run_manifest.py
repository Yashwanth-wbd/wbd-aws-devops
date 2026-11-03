"""Run manifests match data/schemas/run-manifest.schema.json (no Airflow needed)."""

import json
import pathlib
import sys
from datetime import datetime, timezone

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "dags"))

from mmm_lib.manifest import build_manifest, manifest_key  # noqa: E402

jsonschema = pytest.importorskip("jsonschema")
SCHEMA = json.loads((ROOT / "schemas" / "run-manifest.schema.json").read_text())

S3_CONF = {
    "trigger": "s3",
    "business_unit": "streaming",
    "source": {"bucket": "wbd-mmm-dev-landing-use1", "key": "streaming/2026/11/spend.csv", "etag": "abc", "size": 10},
}


def _manifest(states, conf=S3_CONF):
    return build_manifest(
        dag_id="mmm_ingest",
        run_id="s3__0123",
        environment="dev",
        conf=conf,
        task_states=states,
        started_at=datetime(2026, 11, 4, tzinfo=timezone.utc),
    )


@pytest.mark.parametrize(
    ("states", "status"),
    [
        ({"resolve": "success", "transform": "success", "retrain": "success"}, "success"),
        ({"resolve": "success", "transform": "skipped", "retrain": "skipped"}, "success"),
        ({"transform": "skipped"}, "skipped"),
        ({"resolve": "success", "transform": "failed", "retrain": "upstream_failed"}, "failed"),
    ],
)
def test_status_and_schema(states, status):
    manifest = _manifest(states)
    jsonschema.validate(manifest, SCHEMA)
    assert manifest["status"] == status


def test_ondemand_without_source():
    manifest = _manifest({"resolve": "success"}, {"trigger": "ondemand", "business_unit": "all", "requested_by": "arn:aws:sts::1:assumed-role/DevOps/x"})
    jsonschema.validate(manifest, SCHEMA)
    assert manifest["source"] == {"bucket": None, "key": None, "etag": None}


def test_manifest_key():
    assert manifest_key("mmm_ingest", "s3__0123") == "run-manifests/mmm_ingest/s3__0123.json"

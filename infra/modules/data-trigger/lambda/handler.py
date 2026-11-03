"""Start one MWAA DAG run per landed file or per on-demand request.

Events (EventBridge, default bus):
  aws.s3        Object Created in the landing bucket under <business_unit>/...
  mmm.ondemand  "Data refresh requested" with detail {business_unit, request_id, requested_by, reason}

Idempotency: the dag_run_id is derived from bucket + key + etag (or the request_id), so a
redelivered event gets HTTP 409 from Airflow and is treated as done. One file -> one run.
"""

import hashlib
import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

MWAA_ENV = os.environ["MWAA_ENVIRONMENT"]
DAG_ID = os.environ["DAG_ID"]
ENVIRONMENT = os.environ["APP_ENV"]
ONDEMAND_SOURCE = os.environ.get("ONDEMAND_SOURCE", "mmm.ondemand")
BUSINESS_UNITS = set(json.loads(os.environ["BUSINESS_UNITS"]))

mwaa = boto3.client("mwaa")


def _run_id(kind, *parts):
    digest = hashlib.sha256("|".join(parts).encode()).hexdigest()[:32]
    return f"{kind}__{digest}"


def _from_s3(event):
    detail = event["detail"]
    bucket = detail["bucket"]["name"]
    key = detail["object"]["key"]
    etag = detail["object"].get("etag", "")
    business_unit = key.split("/", 1)[0]
    if key.endswith("/") or business_unit not in BUSINESS_UNITS:
        return None, None
    conf = {
        "trigger": "s3",
        "environment": ENVIRONMENT,
        "business_unit": business_unit,
        "source": {"bucket": bucket, "key": key, "etag": etag, "size": detail["object"].get("size")},
        "event_time": event.get("time"),
    }
    return _run_id("s3", bucket, key, etag), conf


def _from_ondemand(event):
    detail = event.get("detail") or {}
    business_unit = detail.get("business_unit", "all")
    if business_unit != "all" and business_unit not in BUSINESS_UNITS:
        raise ValueError(f"unknown business_unit {business_unit!r}")
    request_id = str(detail.get("request_id") or event["id"])
    conf = {
        "trigger": "ondemand",
        "environment": ENVIRONMENT,
        "business_unit": business_unit,
        "request_id": request_id,
        "requested_by": detail.get("requested_by", "unknown"),
        "reason": detail.get("reason", ""),
        "event_time": event.get("time"),
    }
    return _run_id("ondemand", request_id), conf


def lambda_handler(event, _context):
    source = event.get("source")
    if source == "aws.s3":
        run_id, conf = _from_s3(event)
    elif source == ONDEMAND_SOURCE:
        run_id, conf = _from_ondemand(event)
    else:
        raise ValueError(f"unexpected event source {source!r}")

    if run_id is None:
        LOG.info(json.dumps({"result": "ignored", "event_id": event.get("id")}))
        return {"status": "ignored"}

    try:
        resp = mwaa.invoke_rest_api(
            Name=MWAA_ENV,
            Method="POST",
            Path=f"/dags/{DAG_ID}/dagRuns",
            Body={"dag_run_id": run_id, "conf": conf},
        )
    except ClientError as err:
        status = err.response.get("RestApiStatusCode") or err.response.get("Error", {}).get("RestApiStatusCode")
        if str(status) == "409" or "already exists" in str(err):
            LOG.info(json.dumps({"result": "duplicate", "dag_run_id": run_id}))
            return {"status": "duplicate", "dag_run_id": run_id}
        raise

    LOG.info(json.dumps({"result": "started", "dag_run_id": run_id, "conf": conf, "status": resp.get("RestApiStatusCode")}))
    return {"status": "started", "dag_run_id": run_id}

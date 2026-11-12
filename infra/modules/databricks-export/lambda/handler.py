"""Databricks export (DevOps-owned; shipped by Terraform, not by deploy.yml).

Called by the model-refresh and model-monitor state machines; it never moves data itself.
The WBD export job (one per business unit, SSM JOB_IDS_PARAMETER) reads the source catalog and
writes Parquet to output_uri through the Unity Catalog external location on our landing bucket.

  {"action": "start", "business_unit": "<bu>", "output_uri": "s3://...", "purpose": "refresh"|"monitor", "request_id": "<id>"}
      -> {"run_id": <int>, "job_id": <int>}
  {"action": "status", "run_id": <int>, "business_unit": "<bu>", "output_uri": "s3://..."}
      -> {"done": bool, "succeeded": bool, "life_cycle_state": "...", "result_state": "...", "message": "..."}
      On success it writes <output_uri>_manifest.json (run id, time), which the Bronze job checks.

Auth: OAuth machine-to-machine with the service principal in SECRET_ID {"client_id", "client_secret"}.
Databricks 429 / 5xx and network errors raise DatabricksRetryable, which the state machines retry.
"""

import base64
import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

HOST = os.environ["DATABRICKS_HOST"].rstrip("/")
SECRET_ID = os.environ["SECRET_ID"]
JOB_IDS_PARAMETER = os.environ["JOB_IDS_PARAMETER"]
BU_KEYS = json.loads(os.environ.get("BU_KEYS", "{}"))
DEFAULT_KEY = os.environ.get("DEFAULT_KEY", "")
HTTP_TIMEOUT = int(os.environ.get("HTTP_TIMEOUT_SECONDS", "30"))

TERMINAL = {"TERMINATED", "SKIPPED", "INTERNAL_ERROR"}

secrets = boto3.client("secretsmanager")
ssm = boto3.client("ssm")
s3 = boto3.client("s3")

_token = {"value": None, "expires": 0}


class DatabricksRetryable(Exception):
    """Throttling, a Databricks 5xx or a network error - safe to retry."""


class DatabricksExportError(Exception):
    """Bad request or configuration - retrying does not help."""


def _http(method, url, headers, body=None):
    req = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        if exc.code == 429 or exc.code >= 500:
            raise DatabricksRetryable(f"{method} {url}: HTTP {exc.code} {detail}") from exc
        raise DatabricksExportError(f"{method} {url}: HTTP {exc.code} {detail}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise DatabricksRetryable(f"{method} {url}: {exc}") from exc


def token():
    if _token["value"] and _token["expires"] > time.time() + 60:
        return _token["value"]
    sp = json.loads(secrets.get_secret_value(SecretId=SECRET_ID)["SecretString"])
    if not sp.get("client_id") or not sp.get("client_secret"):
        raise DatabricksExportError(f"{SECRET_ID} must hold {{\"client_id\": ..., \"client_secret\": ...}}")
    body = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "all-apis"}).encode()
    basic = base64.b64encode(f"{sp['client_id']}:{sp['client_secret']}".encode()).decode()
    result = _http("POST", f"{HOST}/oidc/v1/token", {"Authorization": f"Basic {basic}", "Content-Type": "application/x-www-form-urlencoded"}, body)
    _token["value"] = result["access_token"]
    _token["expires"] = time.time() + int(result.get("expires_in", 3600))
    return _token["value"]


def api(method, path, payload=None, query=None):
    url = f"{HOST}{path}" + (f"?{urllib.parse.urlencode(query)}" if query else "")
    body = json.dumps(payload).encode() if payload is not None else None
    return _http(method, url, {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, body)


def job_id_for(bu):
    ids = json.loads(ssm.get_parameter(Name=JOB_IDS_PARAMETER)["Parameter"]["Value"] or "{}")
    job_id = int(ids.get(bu, 0) or 0)
    if job_id <= 0:
        raise DatabricksExportError(f"no Databricks export job id for business unit '{bu}' in {JOB_IDS_PARAMETER}")
    return job_id


def split_s3(uri):
    if not uri.startswith("s3://"):
        raise DatabricksExportError(f"output_uri must be an s3:// URI, got {uri!r}")
    bucket, _, key = uri[5:].partition("/")
    return bucket, key if key.endswith("/") or not key else key + "/"


def start(event):
    bu, output_uri = event["business_unit"], event["output_uri"]
    split_s3(output_uri)
    job_id = job_id_for(bu)
    params = {
        "business_unit": bu,
        "output_uri": output_uri,
        "purpose": event.get("purpose", "refresh"),
        "request_id": event.get("request_id", ""),
    }
    request = {"job_id": job_id, "job_parameters": params}
    if params["request_id"]:
        # a retried start of the same request does not launch a second run
        request["idempotency_token"] = params["request_id"][:64]
    result = api("POST", "/api/2.2/jobs/run-now", request)
    log.info("export started: bu=%s job=%s run=%s -> %s", bu, job_id, result["run_id"], output_uri)
    return {"run_id": result["run_id"], "job_id": job_id}


def status(event):
    run = api("GET", "/api/2.2/jobs/runs/get", query={"run_id": int(event["run_id"])})
    state = run.get("state", {})
    life, result = state.get("life_cycle_state", "UNKNOWN"), state.get("result_state", "")
    done = life in TERMINAL
    ok = done and life == "TERMINATED" and result == "SUCCESS"
    if ok:
        bucket, prefix = split_s3(event["output_uri"])
        bu = event["business_unit"]
        manifest = {"run_id": int(event["run_id"]), "business_unit": bu, "output_uri": event["output_uri"], "finished_at": int(time.time())}
        key_id = BU_KEYS.get(bu, DEFAULT_KEY)
        extra = {"ServerSideEncryption": "aws:kms", "SSEKMSKeyId": key_id} if key_id else {}
        s3.put_object(Bucket=bucket, Key=f"{prefix}_manifest.json", Body=json.dumps(manifest).encode(), ContentType="application/json", **extra)
    log.info("export run %s: %s %s", event["run_id"], life, result)
    return {"done": done, "succeeded": ok, "life_cycle_state": life, "result_state": result, "message": state.get("state_message", "")}


def lambda_handler(event, _context):
    action = event.get("action")
    if action == "start":
        return start(event)
    if action == "status":
        return status(event)
    raise DatabricksExportError(f"unknown action {action!r} (start, status)")

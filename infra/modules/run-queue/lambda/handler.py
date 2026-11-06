"""Optimization run dispatcher (DevOps-owned; shipped by Terraform, not by deploy.yml).

SQS event source -> for each run request:
  * invalid body            -> batch-item failure (after max_receive_count it lands in the DLQ)
  * waited too long         -> dropped, counted in ExpiredRunRequests (the planner resubmits)
  * a run slot is free      -> StartExecution named run_id (a duplicate delivery is a no-op)
  * all slots busy          -> batch-item failure; SQS delivers it again after the visibility timeout

The limit is the SSM parameter MAX_RUNS_PARAMETER, read on every batch, so a change applies to the
next batch. It is a soft limit: two concurrent batches can start at most one extra batch of runs.
"""

import json
import logging
import os
import re
import time

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
MAX_RUNS_PARAMETER = os.environ["MAX_RUNS_PARAMETER"]
MAX_QUEUE_WAIT_SECONDS = int(os.environ["MAX_QUEUE_WAIT_SECONDS"])
METRIC_NAMESPACE = os.environ["METRIC_NAMESPACE"]
STATE_MACHINE_NAME = STATE_MACHINE_ARN.rsplit(":", 1)[-1]

REQUIRED = ("run_id", "business_unit", "input_s3_uri")
RUN_ID = re.compile(r"^[A-Za-z0-9_-]{1,80}$")

sfn = boto3.client("stepfunctions")
ssm = boto3.client("ssm")
cloudwatch = boto3.client("cloudwatch")


def max_runs():
    value = ssm.get_parameter(Name=MAX_RUNS_PARAMETER)["Parameter"]["Value"]
    return max(int(value), 0)


def running_runs():
    count = 0
    for page in sfn.get_paginator("list_executions").paginate(stateMachineArn=STATE_MACHINE_ARN, statusFilter="RUNNING"):
        count += len(page["executions"])
    return count


def put_metrics(expired, running):
    dims = [{"Name": "StateMachine", "Value": STATE_MACHINE_NAME}]
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[
            {"MetricName": "ExpiredRunRequests", "Dimensions": dims, "Value": expired, "Unit": "Count"},
            {"MetricName": "RunningRuns", "Dimensions": dims, "Value": running, "Unit": "Count"},
        ],
    )


def parse(record):
    try:
        body = json.loads(record["body"])
    except (TypeError, ValueError):
        return None, "body is not JSON"
    if not isinstance(body, dict):
        return None, "body is not a JSON object"
    missing = [k for k in REQUIRED if not body.get(k)]
    if missing:
        return None, f"missing {', '.join(missing)}"
    if not RUN_ID.match(str(body["run_id"])):
        return None, "run_id must be 1-80 letters, digits, '-' or '_'"
    if not str(body["input_s3_uri"]).startswith("s3://"):
        return None, "input_s3_uri must be an s3:// URI"
    return body, None


def lambda_handler(event, _context):
    limit = max_runs()
    running = running_runs()
    failures, expired, started = [], 0, 0
    now_ms = int(time.time() * 1000)

    for record in event.get("Records", []):
        msg_id = record["messageId"]
        body, error = parse(record)
        if error:
            log.error("invalid run request %s: %s", msg_id, error)
            failures.append({"itemIdentifier": msg_id})
            continue

        run_id = str(body["run_id"])
        waited = (now_ms - int(record["attributes"]["SentTimestamp"])) / 1000
        if waited > MAX_QUEUE_WAIT_SECONDS:
            log.warning("run %s waited %.0fs (limit %ss) - dropped, planner must resubmit", run_id, waited, MAX_QUEUE_WAIT_SECONDS)
            expired += 1
            continue

        if running >= limit:
            log.info("run %s waiting: %s of %s run slots busy", run_id, running, limit)
            failures.append({"itemIdentifier": msg_id})
            continue

        payload = {k: body[k] for k in REQUIRED}
        payload["dry_run"] = bool(body.get("dry_run", False))
        try:
            sfn.start_execution(stateMachineArn=STATE_MACHINE_ARN, name=run_id, input=json.dumps(payload))
            running += 1
            started += 1
            log.info("run %s started (bu=%s, requested_by=%s)", run_id, body["business_unit"], body.get("requested_by", "-"))
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ExecutionAlreadyExists":
                log.info("run %s already started - duplicate delivery ignored", run_id)
                continue
            log.exception("run %s could not be started", run_id)
            failures.append({"itemIdentifier": msg_id})

    put_metrics(expired, running)
    log.info("batch done: started=%s waiting/failed=%s expired=%s running=%s limit=%s", started, len(failures), expired, running, limit)
    return {"batchItemFailures": failures}

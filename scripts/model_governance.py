#!/usr/bin/env python3
"""Model governance for the MMM models in the SageMaker Model Registry.

Used by .github/workflows/model-governance.yml. Thresholds: data/model-thresholds.yaml.
The model-refresh state machine registers every retrained model as PendingManualApproval in the
model package group <prefix>-<business unit>, with ModelMetrics pointing at evaluation.json.

  check-thresholds  validate the thresholds file (CI, offline)
  evaluate-file     evaluate a metrics JSON file against the thresholds (offline, for testing)
  evaluate          evaluate every PendingManualApproval version without a governance tag:
                    tag it passed / failed with the checked metrics; failed -> Rejected (never approvable)
  promote           approve a passed version (after the approval gate), publish its response
                    curves to s3://<models bucket>/curves/<bu>/ (read by the API) and its drift
                    baseline to s3://<models bucket>/baseline/<bu>/ (read by the model-monitor),
                    and write approval.json next to its evaluation.json
  rollback          re-publish the previously approved version and reject the current one

AWS auth: the GitHub OIDC role of the job (gha-model-eval may only reject; gha-model-approve may approve).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

import yaml

STATUS_TAG = "governance_status"
CHECKS_TAG = "governance_checks"
PREVIOUS_TAG = "previous_approved_version"
ENV_SHORT = {"dev": "dev", "staging": "stg", "prod": "prd"}


# ------------------------------------------------------------------ thresholds (offline)
def load_thresholds(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    errors = []
    for key in ("model_package_group", "curves_prefix", "baseline_prefix", "business_units"):
        if key not in cfg:
            errors.append(f"missing top-level key {key!r}")
    for bu, spec in (cfg.get("business_units") or {}).items():
        metrics = (spec or {}).get("metrics") or {}
        if not metrics:
            errors.append(f"{bu}: no metrics")
        drift = (spec or {}).get("drift")
        if drift is not None:
            threshold = drift.get("threshold") if isinstance(drift, dict) else None
            if not isinstance(threshold, (int, float)) or isinstance(threshold, bool) or not 0 < threshold < 1:
                errors.append(f"{bu}.drift: use {{threshold: x}} with 0 < x < 1")
        for name, rule in metrics.items():
            if not isinstance(rule, dict) or not set(rule) <= {"min", "max"} or not rule:
                errors.append(f"{bu}.{name}: use {{min: x}}, {{max: y}} or both")
                continue
            for bound in rule.values():
                if not isinstance(bound, (int, float)) or isinstance(bound, bool):
                    errors.append(f"{bu}.{name}: bounds must be numbers")
    if errors:
        raise SystemExit("invalid thresholds:\n  " + "\n  ".join(errors))
    return cfg


def evaluate_metrics(metrics: dict, rules: dict) -> list[dict]:
    """One result per rule; a missing or non-finite metric fails."""
    results = []
    for name, rule in sorted(rules.items()):
        value = metrics.get(name)
        ok = isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
        if ok and "min" in rule:
            ok = value >= rule["min"]
        if ok and "max" in rule:
            ok = value <= rule["max"]
        results.append({"metric": name, "value": value, **rule, "passed": bool(ok)})
    return results


def summary(results: list[dict]) -> str:
    parts = []
    for r in results:
        bounds = " ".join(f"{k}={r[k]}" for k in ("min", "max") if k in r)
        parts.append(f"{r['metric']}={r['value']} ({bounds}) {'ok' if r['passed'] else 'FAIL'}")
    return "; ".join(parts)


# ------------------------------------------------------------------ SageMaker Model Registry
def clients():
    import boto3  # noqa: PLC0415

    return boto3.client("sagemaker"), boto3.client("s3")


def group_name(cfg: dict, environment: str, bu: str) -> str:
    return cfg["model_package_group"].format(prefix=f"mmm-{ENV_SHORT[environment]}", business_unit=bu)


def package_arn(sm, group: str, version: str) -> str:
    for page in sm.get_paginator("list_model_packages").paginate(ModelPackageGroupName=group):
        for p in page["ModelPackageSummaryList"]:
            if str(p["ModelPackageVersion"]) == str(version):
                return p["ModelPackageArn"]
    raise SystemExit(f"{group}: version {version} not found")


def packages(sm, group: str, status: str) -> list[dict]:
    """Versions with the given approval status, newest first."""
    out = []
    pages = sm.get_paginator("list_model_packages").paginate(
        ModelPackageGroupName=group, ModelApprovalStatus=status, SortBy="CreationTime", SortOrder="Descending"
    )
    for page in pages:
        out.extend(page["ModelPackageSummaryList"])
    return out


def tags(sm, arn: str) -> dict:
    return {t["Key"]: t["Value"] for t in sm.list_tags(ResourceArn=arn).get("Tags", [])}


def tag(sm, arn: str, **values: str) -> None:
    sm.add_tags(ResourceArn=arn, Tags=[{"Key": k, "Value": str(v)[:256]} for k, v in values.items()])


def split_s3(uri: str) -> tuple[str, str]:
    u = urlparse(uri)
    return u.netloc, u.path.lstrip("/")


def evaluation_uri(sm, arn: str) -> str:
    pkg = sm.describe_model_package(ModelPackageName=arn)
    try:
        return pkg["ModelMetrics"]["ModelQuality"]["Statistics"]["S3Uri"]
    except KeyError:
        return ""


def read_metrics(s3, uri: str) -> dict:
    if not uri:
        return {}
    bucket, key = split_s3(uri)
    return json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())


def list_keys(s3, bucket: str, prefix: str) -> list[str]:
    return [o["Key"] for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix) for o in page.get("Contents", [])]


def publish_curves(s3, cfg: dict, bu: str, eval_uri: str, models_bucket: str, arn: str) -> int:
    """Replace curves/<bu>/ with <evaluation prefix>/curves/ of the approved version."""
    return publish_folder(s3, eval_uri, "curves", cfg["curves_prefix"].format(business_unit=bu), models_bucket, arn, required=True)


def publish_baseline(s3, cfg: dict, bu: str, eval_uri: str, models_bucket: str, arn: str) -> int:
    """Replace baseline/<bu>/ (drift reference) with <evaluation prefix>/baseline/ of the approved version."""
    count = publish_folder(s3, eval_uri, "baseline", cfg["baseline_prefix"].format(business_unit=bu), models_bucket, arn, required=False)
    if count == 0:
        print(f"::warning::{bu}: no baseline/ in the evaluation output - the drift check fails until a version with a baseline is approved")
    return count


def publish_folder(s3, eval_uri: str, folder: str, dst_prefix: str, models_bucket: str, arn: str, required: bool) -> int:
    src_bucket, eval_key = split_s3(eval_uri)
    src_prefix = eval_key.rsplit("/", 1)[0] + f"/{folder}/"
    src = list_keys(s3, src_bucket, src_prefix)
    if not src and required:
        raise SystemExit(f"no {folder} under s3://{src_bucket}/{src_prefix}")
    old = list_keys(s3, models_bucket, dst_prefix)
    wanted = set()
    for key in src:
        dst = dst_prefix + key[len(src_prefix):]
        wanted.add(dst)
        s3.copy_object(Bucket=models_bucket, Key=dst, CopySource={"Bucket": src_bucket, "Key": key}, ServerSideEncryption="aws:kms")
    marker = dst_prefix + "_model_package.json"
    wanted.add(marker)
    s3.put_object(Bucket=models_bucket, Key=marker, ServerSideEncryption="aws:kms",
                  Body=json.dumps({"model_package_arn": arn, "published_at": datetime.now(timezone.utc).isoformat()}).encode())
    for key in old:
        if key not in wanted:
            s3.delete_object(Bucket=models_bucket, Key=key)
    return len(src)


def write_approval(s3, eval_uri: str, record: dict) -> str:
    """approval.json next to evaluation.json: who approved which version, when, with which checks."""
    bucket, eval_key = split_s3(eval_uri)
    key = eval_key.rsplit("/", 1)[0] + "/approval.json"
    s3.put_object(Bucket=bucket, Key=key, ServerSideEncryption="aws:kms", ContentType="application/json",
                  Body=json.dumps(record, indent=2, default=str).encode())
    return f"s3://{bucket}/{key}"


def write_output(key: str, value) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={json.dumps(value, separators=(',', ':'))}\n")


def write_summary(lines: list[str]) -> None:
    out = os.environ.get("GITHUB_STEP_SUMMARY")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------ commands
def cmd_evaluate(args) -> int:
    cfg = load_thresholds(args.thresholds)
    sm, s3 = clients()
    bus = [args.business_unit] if args.business_unit != "all" else list(cfg["business_units"])
    report, passed = [], []

    for bu in bus:
        group = group_name(cfg, args.environment, bu)
        if args.version:
            candidates = [{"ModelPackageArn": package_arn(sm, group, args.version), "ModelPackageVersion": args.version}]
        else:
            candidates = packages(sm, group, "PendingManualApproval")
        if not candidates:
            report.append({"business_unit": bu, "group": group, "status": "no-candidate"})
        for c in candidates:
            arn, version = c["ModelPackageArn"], str(c["ModelPackageVersion"])
            existing = tags(sm, arn).get(STATUS_TAG)
            if existing and not args.version:
                report.append({"business_unit": bu, "group": group, "version": version, "status": f"already-{existing}"})
                continue
            results = evaluate_metrics(read_metrics(s3, evaluation_uri(sm, arn)), cfg["business_units"][bu]["metrics"])
            ok = all(r["passed"] for r in results)
            status = "passed" if ok else "failed"
            tag(sm, arn, **{STATUS_TAG: status, CHECKS_TAG: summary(results), "governance_evaluated_at": datetime.now(timezone.utc).isoformat()})
            if ok:
                passed.append({"business_unit": bu, "version": version})
            else:
                # Failed versions stay in the registry with their metrics but can never be approved.
                sm.update_model_package(ModelPackageArn=arn, ModelApprovalStatus="Rejected",
                                        ApprovalDescription=f"Failed thresholds: {summary(results)}"[:1024])
                print(f"::warning::{group} v{version} FAILED governance: {summary(results)}")
            report.append({"business_unit": bu, "group": group, "version": version, "status": status, "checks": results})

    with open(args.report, "w", encoding="utf-8") as fh:
        json.dump({"environment": args.environment, "run": args.run_url, "results": report}, fh, indent=2, default=str)
    write_output("passed", passed)
    lines = [f"### Model evaluation - {args.environment}", "", "| Business unit | Version | Result | Checks |", "|---|---|---|---|"]
    lines += [f"| {r['business_unit']} | {r.get('version', '-')} | {r['status']} | {summary(r.get('checks', [])) or '-'} |" for r in report]
    write_summary(lines)
    print(json.dumps(report, indent=2, default=str))
    return 0


def cmd_promote(args) -> int:
    cfg = load_thresholds(args.thresholds)
    sm, s3 = clients()
    group = group_name(cfg, args.environment, args.business_unit)
    arn = package_arn(sm, group, args.version)
    status = tags(sm, arn).get(STATUS_TAG)
    if status != "passed":
        print(f"::error::{group} v{args.version} has {STATUS_TAG}={status!r}; only passed versions can be approved")
        return 1
    approved = packages(sm, group, "Approved")
    current = approved[0] if approved else None
    if current is not None and str(current["ModelPackageVersion"]) == str(args.version):
        print(f"{group} v{args.version} is already the approved version")
        return 0
    eval_uri = evaluation_uri(sm, arn)
    count = publish_curves(s3, cfg, args.business_unit, eval_uri, args.models_bucket, arn)
    baseline = publish_baseline(s3, cfg, args.business_unit, eval_uri, args.models_bucket, arn)
    sm.update_model_package(ModelPackageArn=arn, ModelApprovalStatus="Approved",
                            ApprovalDescription=f"Approved by {args.approved_by} - {args.run_url}"[:1024])
    previous = str(current["ModelPackageVersion"]) if current else "none"
    approved_at = datetime.now(timezone.utc).isoformat()
    tag(sm, arn, **{PREVIOUS_TAG: previous, "approved_at": approved_at, "approved_by": args.approved_by})
    record = write_approval(s3, eval_uri, {
        "environment": args.environment, "business_unit": args.business_unit, "model_package_arn": arn,
        "version": str(args.version), "previous_version": previous, "approved_by": args.approved_by,
        "approved_at": approved_at, "run": args.run_url, "checks": tags(sm, arn).get(CHECKS_TAG, ""),
        "curve_files": count, "baseline_files": baseline,
    })
    write_summary([f"### Approved {group} v{args.version}",
                   f"curves: {count} files - baseline: {baseline} files - previous: {previous} - approved by: {args.approved_by} - record: {record}"])
    print(f"{group}: approved v{args.version} (was {previous}); {count} curve files, {baseline} baseline files published; {record}")
    return 0


def cmd_rollback(args) -> int:
    cfg = load_thresholds(args.thresholds)
    sm, s3 = clients()
    group = group_name(cfg, args.environment, args.business_unit)
    approved = packages(sm, group, "Approved")
    if not approved:
        print(f"::error::{group}: no approved version")
        return 1
    current = approved[0]
    target = args.version or tags(sm, current["ModelPackageArn"]).get(PREVIOUS_TAG)
    if not target or target == "none":
        print(f"::error::{group}: no {PREVIOUS_TAG} tag on v{current['ModelPackageVersion']}; pass --version")
        return 1
    arn = package_arn(sm, group, target)
    publish_curves(s3, cfg, args.business_unit, evaluation_uri(sm, arn), args.models_bucket, arn)
    publish_baseline(s3, cfg, args.business_unit, evaluation_uri(sm, arn), args.models_bucket, arn)
    sm.update_model_package(ModelPackageArn=current["ModelPackageArn"], ModelApprovalStatus="Rejected",
                            ApprovalDescription=f"Rolled back to v{target} - {args.run_url}"[:1024])
    tag(sm, current["ModelPackageArn"], **{STATUS_TAG: "rolled-back"})
    write_summary([f"### Rolled back {group}: v{current['ModelPackageVersion']} -> v{target}"])
    print(f"{group}: rolled back v{current['ModelPackageVersion']} -> v{target}")
    return 0


def cmd_check_thresholds(args) -> int:
    cfg = load_thresholds(args.thresholds)
    print(f"thresholds OK: {', '.join(cfg['business_units'])}")
    return 0


def cmd_evaluate_file(args) -> int:
    cfg = load_thresholds(args.thresholds)
    with open(args.metrics, encoding="utf-8") as fh:
        metrics = json.load(fh)
    results = evaluate_metrics(metrics, cfg["business_units"][args.business_unit]["metrics"])
    print(summary(results))
    return 0 if all(r["passed"] for r in results) else 2


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--thresholds", default="data/model-thresholds.yaml")
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("check-thresholds").set_defaults(func=cmd_check_thresholds)

    f = sub.add_parser("evaluate-file")
    f.add_argument("--business-unit", required=True)
    f.add_argument("--metrics", required=True, help="JSON object {metric: value}")
    f.set_defaults(func=cmd_evaluate_file)

    for name, func in (("evaluate", cmd_evaluate), ("promote", cmd_promote), ("rollback", cmd_rollback)):
        s = sub.add_parser(name)
        s.add_argument("--environment", required=True, choices=sorted(ENV_SHORT))
        s.add_argument("--business-unit", default="all" if name == "evaluate" else None, required=name != "evaluate")
        s.add_argument("--version", default=None)
        s.add_argument("--run-url", default="")
        if name == "evaluate":
            s.add_argument("--report", default="model-evaluation.json")
        else:
            s.add_argument("--models-bucket", required=True)
        if name == "promote":
            s.add_argument("--approved-by", required=True)
        s.set_defaults(func=func)

    args = p.parse_args(argv)
    if args.command == "promote" and not args.version:
        p.error("promote needs --version")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

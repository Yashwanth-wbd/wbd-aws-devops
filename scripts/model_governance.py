#!/usr/bin/env python3
"""Model governance for the MMM models in the MLflow (Unity Catalog) registry.

Used by .github/workflows/model-governance.yml. Thresholds: data/model-thresholds.yaml.

  check-thresholds  validate the thresholds file (CI, offline)
  evaluate-file     evaluate a metrics JSON file against the thresholds (offline, for testing)
  evaluate          evaluate every version that has the "candidate" alias and no governance tag:
                    tag it passed / failed with the checked metrics; failed -> candidate alias removed
  promote           move the "production" alias to a passed version (after the approval gate)
  rollback          move "production" back to the version it replaced

Databricks auth: databricks-sdk unified auth (DATABRICKS_HOST + DATABRICKS_CLIENT_ID +
DATABRICKS_AUTH_TYPE=github-oidc in GitHub Actions; no secret). The short-lived token is handed
to MLflow as DATABRICKS_TOKEN for this process only.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone

import yaml

STATUS_TAG = "governance_status"
CHECKS_TAG = "governance_checks"
PREVIOUS_TAG = "previous_production_version"


# ------------------------------------------------------------------ thresholds (offline)
def load_thresholds(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    errors = []
    for key in ("model_name", "candidate_alias", "production_alias", "business_units"):
        if key not in cfg:
            errors.append(f"missing top-level key {key!r}")
    for bu, spec in (cfg.get("business_units") or {}).items():
        metrics = (spec or {}).get("metrics") or {}
        if not metrics:
            errors.append(f"{bu}: no metrics")
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
        ok = isinstance(value, (int, float)) and math.isfinite(value)
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


# ------------------------------------------------------------------ MLflow (Unity Catalog registry)
def mlflow_client():
    from databricks.sdk.core import Config  # noqa: PLC0415
    from mlflow import MlflowClient  # noqa: PLC0415

    cfg = Config()
    os.environ["DATABRICKS_HOST"] = cfg.host
    os.environ["DATABRICKS_TOKEN"] = cfg.authenticate()["Authorization"].removeprefix("Bearer ")
    os.environ.pop("DATABRICKS_AUTH_TYPE", None)
    os.environ.pop("DATABRICKS_CLIENT_ID", None)
    return MlflowClient(tracking_uri="databricks", registry_uri="databricks-uc")


def alias_version(client, name: str, alias: str):
    from mlflow.exceptions import MlflowException  # noqa: PLC0415

    try:
        return client.get_model_version_by_alias(name, alias)
    except MlflowException:
        return None


def model_name(cfg: dict, catalog: str, bu: str) -> str:
    return cfg["model_name"].format(catalog=catalog, business_unit=bu)


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


def cmd_evaluate(args) -> int:
    cfg = load_thresholds(args.thresholds)
    client = mlflow_client()
    bus = [args.business_unit] if args.business_unit != "all" else list(cfg["business_units"])
    report, passed = [], []

    for bu in bus:
        name = model_name(cfg, args.catalog, bu)
        if args.version:
            mv = client.get_model_version(name, args.version)
        else:
            mv = alias_version(client, name, cfg["candidate_alias"])
        if mv is None:
            report.append({"business_unit": bu, "model": name, "status": "no-candidate"})
            continue
        if mv.tags.get(STATUS_TAG) and not args.version:
            report.append({"business_unit": bu, "model": name, "version": mv.version, "status": f"already-{mv.tags[STATUS_TAG]}"})
            continue

        metrics = client.get_run(mv.run_id).data.metrics if mv.run_id else {}
        results = evaluate_metrics(metrics, cfg["business_units"][bu]["metrics"])
        ok = all(r["passed"] for r in results)
        status = "passed" if ok else "failed"
        client.set_model_version_tag(name, mv.version, STATUS_TAG, status)
        client.set_model_version_tag(name, mv.version, CHECKS_TAG, summary(results)[:5000])
        client.set_model_version_tag(name, mv.version, "governance_evaluated_at", datetime.now(timezone.utc).isoformat())
        client.set_model_version_tag(name, mv.version, "governance_run", args.run_url or "")
        if ok:
            passed.append({"business_unit": bu, "version": str(mv.version)})
        else:
            # Failed candidates stay in the registry (with their metrics and tags) but lose the alias.
            client.delete_registered_model_alias(name, cfg["candidate_alias"])
            print(f"::warning::{name} v{mv.version} FAILED governance: {summary(results)}")
        report.append({"business_unit": bu, "model": name, "version": mv.version, "run_id": mv.run_id, "status": status, "checks": results})

    with open(args.report, "w", encoding="utf-8") as fh:
        json.dump({"environment": args.environment, "catalog": args.catalog, "results": report}, fh, indent=2, default=str)
    write_output("passed", passed)
    lines = [f"### Model evaluation - {args.environment}", "", "| Business unit | Version | Result | Checks |", "|---|---|---|---|"]
    lines += [f"| {r['business_unit']} | {r.get('version', '-')} | {r['status']} | {summary(r.get('checks', [])) or '-'} |" for r in report]
    write_summary(lines)
    print(json.dumps(report, indent=2, default=str))
    return 0


def cmd_promote(args) -> int:
    cfg = load_thresholds(args.thresholds)
    client = mlflow_client()
    name = model_name(cfg, args.catalog, args.business_unit)
    mv = client.get_model_version(name, args.version)
    if mv.tags.get(STATUS_TAG) != "passed":
        print(f"::error::{name} v{args.version} has {STATUS_TAG}={mv.tags.get(STATUS_TAG)!r}; only passed versions can be promoted")
        return 1
    current = alias_version(client, name, cfg["production_alias"])
    if current is not None and str(current.version) == str(args.version):
        print(f"{name} v{args.version} is already {cfg['production_alias']}")
        return 0
    if current is not None:
        client.set_model_version_tag(name, mv.version, PREVIOUS_TAG, str(current.version))
    client.set_registered_model_alias(name, cfg["production_alias"], mv.version)
    client.set_model_version_tag(name, mv.version, "promoted_at", datetime.now(timezone.utc).isoformat())
    client.set_model_version_tag(name, mv.version, "promoted_by", args.approved_by)
    client.set_model_version_tag(name, mv.version, "promotion_run", args.run_url or "")
    if alias_version(client, name, cfg["candidate_alias"]) is not None:
        client.delete_registered_model_alias(name, cfg["candidate_alias"])
    write_summary([f"### Promoted {name} v{mv.version} to `{cfg['production_alias']}`",
                   f"previous: {getattr(current, 'version', 'none')} - approved by: {args.approved_by}"])
    print(f"{name}: {cfg['production_alias']} -> v{mv.version} (was {getattr(current, 'version', 'none')})")
    return 0


def cmd_rollback(args) -> int:
    cfg = load_thresholds(args.thresholds)
    client = mlflow_client()
    name = model_name(cfg, args.catalog, args.business_unit)
    current = alias_version(client, name, cfg["production_alias"])
    previous = args.version or (current.tags.get(PREVIOUS_TAG) if current else None)
    if not previous:
        print(f"::error::{name}: no {PREVIOUS_TAG} tag on the production version; pass --version")
        return 1
    client.set_registered_model_alias(name, cfg["production_alias"], previous)
    if current is not None:
        client.set_model_version_tag(name, current.version, STATUS_TAG, "rolled-back")
    client.set_model_version_tag(name, previous, "rolled_back_to_at", datetime.now(timezone.utc).isoformat())
    write_summary([f"### Rolled back {name}: `{cfg['production_alias']}` -> v{previous} (was v{getattr(current, 'version', '?')})"])
    print(f"{name}: {cfg['production_alias']} -> v{previous}")
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
        s.add_argument("--environment", required=True)
        s.add_argument("--catalog", required=True)
        s.add_argument("--business-unit", default="all" if name == "evaluate" else None, required=name != "evaluate")
        s.add_argument("--version", default=None)
        s.add_argument("--run-url", default="")
        if name == "evaluate":
            s.add_argument("--report", default="model-evaluation.json")
        if name == "promote":
            s.add_argument("--approved-by", required=True)
        s.set_defaults(func=func)

    args = p.parse_args(argv)
    if args.command == "promote" and not args.version:
        p.error("promote needs --version")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

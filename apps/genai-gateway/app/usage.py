"""Daily token quotas per business unit and the MMM/GenAI token metric (CloudWatch EMF)."""

import json
import threading
import time
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any


def load_quotas(ssm_client: Any, param_path: str) -> dict[str, int]:
    """Reads <param_path>/token_quota/<bu> (written by Terraform from genai_token_quotas)."""
    prefix = f"{param_path}/token_quota/"
    quotas: dict[str, int] = {}
    for page in ssm_client.get_paginator("get_parameters_by_path").paginate(Path=prefix.rstrip("/")):
        for p in page.get("Parameters", []):
            quotas[p["Name"].removeprefix(prefix)] = int(p["Value"])
    return quotas


class QuotaTracker:
    """Per-task soft limit; the CloudWatch alarm on the summed metric is the cross-task control."""

    def __init__(self, quotas: dict[str, int], today: Callable[[], str] | None = None) -> None:
        self._quotas = quotas
        self._today = today or (lambda: datetime.now(UTC).strftime("%Y-%m-%d"))
        self._day = self._today()
        self._used: dict[str, int] = {}
        self._lock = threading.Lock()

    def known(self, business_unit: str) -> bool:
        return business_unit in self._quotas

    def remaining(self, business_unit: str) -> int:
        with self._lock:
            self._roll()
            return self._quotas.get(business_unit, 0) - self._used.get(business_unit, 0)

    def add(self, business_unit: str, tokens: int) -> None:
        with self._lock:
            self._roll()
            self._used[business_unit] = self._used.get(business_unit, 0) + tokens

    def _roll(self) -> None:
        day = self._today()
        if day != self._day:
            self._day, self._used = day, {}


def token_metric(namespace: str, environment: str, business_unit: str, tokens: int) -> str:
    """One EMF line; CloudWatch turns it into the Tokens metric the per-BU alarms watch."""
    return json.dumps(
        {
            "_aws": {
                "Timestamp": int(time.time() * 1000),
                "CloudWatchMetrics": [
                    {
                        "Namespace": namespace,
                        "Dimensions": [["Environment", "BusinessUnit"]],
                        "Metrics": [{"Name": "Tokens", "Unit": "Count"}],
                    }
                ],
            },
            "Environment": environment,
            "BusinessUnit": business_unit,
            "Tokens": tokens,
        }
    )

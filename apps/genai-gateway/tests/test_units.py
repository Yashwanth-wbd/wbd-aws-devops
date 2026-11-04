import json
from typing import Any

from app import grounding
from app.bedrock import Source
from app.config import Settings
from app.usage import QuotaTracker, load_quotas, token_metric


def test_settings_from_env(monkeypatch: Any) -> None:
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.setenv("GENAI_ENABLED", "True")
    monkeypatch.setenv("GENAI_MODEL_ID", "m")
    monkeypatch.delenv("GENAI_GUARDRAIL_ID", raising=False)
    monkeypatch.delenv("GENAI_GUARDRAIL_VERSION", raising=False)
    monkeypatch.delenv("GENAI_PARAM_PATH", raising=False)

    settings = Settings.from_env()

    assert settings.enabled is True
    assert settings.param_path == "/mmm/staging/genai"
    assert settings.missing() == ["GENAI_GUARDRAIL_ID", "GENAI_GUARDRAIL_VERSION"]


def test_numbers_are_normalised() -> None:
    sources = [Source("S1", "Spend 1,500,000 and ROI 2.40")]
    result = grounding.check("Spend 1500000 [S1], ROI 2.4 [S1].", sources)
    assert result.unverified_numbers == []
    assert result.citations == ["S1"]
    assert result.grounded is True


def test_answer_without_citation_is_not_grounded() -> None:
    assert grounding.check("No numbers here.", [Source("S1", "x")]).grounded is False


def test_quota_tracker_resets_each_day() -> None:
    day = ["2026-11-04"]
    tracker = QuotaTracker({"bu": 100}, today=lambda: day[0])
    tracker.add("bu", 100)
    assert tracker.remaining("bu") == 0
    day[0] = "2026-11-05"
    assert tracker.remaining("bu") == 100
    assert tracker.known("bu") and not tracker.known("other")


class FakeSsm:
    def get_paginator(self, name: str) -> "FakeSsm":
        assert name == "get_parameters_by_path"
        return self

    def paginate(self, Path: str) -> list[dict[str, Any]]:
        assert Path == "/mmm/dev/genai/token_quota"
        return [{"Parameters": [{"Name": "/mmm/dev/genai/token_quota/streaming", "Value": "1000"}]}]


def test_load_quotas() -> None:
    assert load_quotas(FakeSsm(), "/mmm/dev/genai") == {"streaming": 1000}


def test_token_metric_is_emf() -> None:
    line = json.loads(token_metric("MMM/GenAI", "dev", "streaming", 42))
    assert line["Tokens"] == 42
    assert line["_aws"]["CloudWatchMetrics"][0]["Dimensions"] == [["Environment", "BusinessUnit"]]

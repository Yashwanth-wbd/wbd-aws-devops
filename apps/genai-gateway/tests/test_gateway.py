from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.bedrock import BedrockGateway, Source
from app.config import Settings
from app.main import create_app
from app.usage import QuotaTracker

SETTINGS = Settings(
    environment="dev",
    region="us-east-1",
    enabled=True,
    model_id="anthropic.claude-3-5-sonnet-20240620-v1:0",
    guardrail_id="gr-123",
    guardrail_version="1",
    param_path="/mmm/dev/genai",
    metrics_namespace="MMM/GenAI",
)

BODY = {
    "business_unit": "streaming",
    "question": "Why did the optimizer move budget to CTV?",
    "sources": [{"id": "S1", "text": "CTV ROI is 2.4 versus 1.1 for linear; budget moved 1,500,000 USD."}],
}


class FakeClient:
    def __init__(self, response: dict[str, Any] | None = None, error: Exception | None = None) -> None:
        self.response = response or {}
        self.error = error
        self.requests: list[dict[str, Any]] = []

    def converse(self, **request: Any) -> dict[str, Any]:
        self.requests.append(request)
        if self.error:
            raise self.error
        return self.response


def reply(text: str, stop: str = "end_turn") -> dict[str, Any]:
    return {
        "output": {"message": {"content": [{"text": text}]}},
        "stopReason": stop,
        "usage": {"inputTokens": 120, "outputTokens": 30},
    }


def client_for(fake: FakeClient, settings: Settings = SETTINGS, quota: int = 1_000_000) -> TestClient:
    gateway = BedrockGateway(fake, settings.model_id, settings.guardrail_id, settings.guardrail_version)
    return TestClient(create_app(settings, gateway, QuotaTracker({"streaming": quota})))


def test_health() -> None:
    response = client_for(FakeClient()).get("/health")
    assert response.status_code == 200
    assert response.json()["genai_enabled"] is True


def test_every_call_carries_the_guardrail_and_grounding_sources() -> None:
    fake = FakeClient(reply("CTV returns 2.4 per dollar [S1]."))
    response = client_for(fake).post("/v1/explain", json=BODY, headers={"X-User-Id": "planner1"})

    assert response.status_code == 200
    request = fake.requests[0]
    assert request["guardrailConfig"] == {
        "guardrailIdentifier": "gr-123",
        "guardrailVersion": "1",
        "trace": "enabled",
    }
    qualifiers = [part["guardContent"]["text"]["qualifiers"] for part in request["messages"][0]["content"]]
    assert qualifiers == [["grounding_source"], ["query"]]
    body = response.json()
    assert body["grounded"] is True
    assert body["ai_generated"] is True
    assert body["citations"] == ["S1"]


def test_invented_numbers_and_unknown_sources_are_flagged() -> None:
    fake = FakeClient(reply("CTV returns 3.7 per dollar [S1] [S9]."))
    body = client_for(fake).post("/v1/explain", json=BODY).json()

    assert body["grounded"] is False
    assert body["unverified_numbers"] == ["3.7"]
    assert body["unknown_citations"] == ["S9"]


def test_guardrail_intervention_is_never_grounded() -> None:
    fake = FakeClient(reply("Blocked by policy.", stop="guardrail_intervened"))
    body = client_for(fake).post("/v1/explain", json=BODY).json()

    assert body["intervened"] is True
    assert body["grounded"] is False


def test_disabled_flag_returns_503() -> None:
    disabled = Settings(**{**SETTINGS.__dict__, "enabled": False})
    response = client_for(FakeClient(), settings=disabled).post("/v1/explain", json=BODY)
    assert response.status_code == 503


def test_unknown_business_unit_is_rejected() -> None:
    response = client_for(FakeClient()).post("/v1/explain", json={**BODY, "business_unit": "news"})
    assert response.status_code == 403


def test_quota_is_enforced_per_business_unit() -> None:
    fake = FakeClient(reply("CTV ROI is 2.4 [S1]."))
    client = client_for(fake, quota=150)

    assert client.post("/v1/explain", json=BODY).status_code == 200
    assert client.post("/v1/explain", json=BODY).status_code == 429
    assert len(fake.requests) == 1


@pytest.mark.parametrize(("code", "status"), [("ThrottlingException", 429), ("AccessDeniedException", 502)])
def test_bedrock_errors(code: str, status: int) -> None:
    error = Exception(code)
    error.response = {"Error": {"Code": code}}  # type: ignore[attr-defined]
    response = client_for(FakeClient(error=error)).post("/v1/explain", json=BODY)
    assert response.status_code == status


def test_request_validation() -> None:
    response = client_for(FakeClient()).post("/v1/explain", json={**BODY, "sources": []})
    assert response.status_code == 422


def test_build_request_joins_sources() -> None:
    gateway = BedrockGateway(FakeClient(), "m", "g", "2")
    request = gateway.build_request("q", [Source("A", "one"), Source("B", "two")], 10)
    assert request["messages"][0]["content"][0]["guardContent"]["text"]["text"] == "[A]\none\n\n[B]\ntwo"
    assert request["inferenceConfig"] == {"maxTokens": 10, "temperature": 0}

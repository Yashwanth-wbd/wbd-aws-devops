"""GenAI gateway: internal service the API calls through Service Connect (http://genai-gateway:8080)."""

import json
import logging
import sys
import uuid
from typing import Annotated, Any

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from app import grounding
from app.bedrock import BedrockGateway, Source
from app.config import Settings
from app.usage import QuotaTracker, load_quotas, token_metric

log = logging.getLogger("genai-gateway")

ID_PATTERN = r"^[A-Za-z0-9_.-]{1,64}$"


class SourceIn(BaseModel):
    id: str = Field(pattern=ID_PATTERN)
    text: str = Field(min_length=1, max_length=20_000)


class ExplainRequest(BaseModel):
    business_unit: str = Field(pattern=r"^[a-z0-9-]{1,32}$")
    question: str = Field(min_length=1, max_length=4_000)
    sources: list[SourceIn] = Field(min_length=1, max_length=20)
    max_tokens: int = Field(default=800, ge=1, le=2_000)


class ExplainResponse(BaseModel):
    request_id: str
    answer: str
    ai_generated: bool = True
    grounded: bool
    intervened: bool
    citations: list[str]
    unknown_citations: list[str]
    unverified_numbers: list[str]
    model_id: str
    guardrail_version: str
    input_tokens: int
    output_tokens: int


def _event(level: int, event: str, **fields: Any) -> None:
    # Metadata only: full prompts and answers are in the Bedrock invocation logs (encrypted bucket).
    log.log(level, json.dumps({"level": logging.getLevelName(level), "event": event, **fields}))


def create_app(settings: Settings, gateway: BedrockGateway | None, quotas: QuotaTracker) -> FastAPI:
    app = FastAPI(title="mmm-genai-gateway", docs_url=None, redoc_url=None)

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {
            "status": "ok",
            "genai_enabled": settings.enabled,
            "model_id": settings.model_id,
            "guardrail_version": settings.guardrail_version,
        }

    @app.post("/v1/explain")
    def explain(
        body: ExplainRequest,
        x_user_id: Annotated[str | None, Header()] = None,
        x_request_id: Annotated[str | None, Header()] = None,
    ) -> ExplainResponse:
        request_id = x_request_id or str(uuid.uuid4())
        if not settings.enabled or gateway is None:
            raise HTTPException(503, "GenAI is turned off in this environment")
        if not quotas.known(body.business_unit):
            raise HTTPException(403, f"No GenAI quota for business unit {body.business_unit}")
        if quotas.remaining(body.business_unit) <= 0:
            raise HTTPException(429, "Daily GenAI token quota reached for this business unit")

        sources = [Source(id=s.id, text=s.text) for s in body.sources]
        try:
            answer = gateway.ask(body.question, sources, body.max_tokens)
        except Exception as exc:
            code = getattr(exc, "response", {}).get("Error", {}).get("Code", type(exc).__name__)
            _event(
                logging.ERROR,
                "bedrock_error",
                request_id=request_id,
                business_unit=body.business_unit,
                error=code,
            )
            status = 429 if code == "ThrottlingException" else 502
            raise HTTPException(status, "The model is not available right now") from exc

        tokens = answer.input_tokens + answer.output_tokens
        quotas.add(body.business_unit, tokens)
        print(
            token_metric(settings.metrics_namespace, settings.environment, body.business_unit, tokens),
            flush=True,
        )

        result = grounding.check(answer.text, sources)
        _event(
            logging.INFO,
            "explain",
            request_id=request_id,
            user=x_user_id,
            business_unit=body.business_unit,
            sources=[s.id for s in sources],
            model_id=settings.model_id,
            guardrail_version=settings.guardrail_version,
            intervened=answer.intervened,
            grounded=result.grounded,
            unverified_numbers=len(result.unverified_numbers),
            tokens=tokens,
        )
        return ExplainResponse(
            request_id=request_id,
            answer=answer.text,
            grounded=result.grounded and not answer.intervened,
            intervened=answer.intervened,
            citations=result.citations,
            unknown_citations=result.unknown_citations,
            unverified_numbers=result.unverified_numbers,
            model_id=settings.model_id,
            guardrail_version=settings.guardrail_version,
            input_tokens=answer.input_tokens,
            output_tokens=answer.output_tokens,
        )

    return app


def build() -> FastAPI:  # pragma: no cover - uvicorn --factory app.main:build (real AWS clients)
    import boto3

    logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
    settings = Settings.from_env()
    gateway: BedrockGateway | None = None
    quotas = QuotaTracker({})
    if settings.enabled:
        missing = settings.missing()
        if missing:
            raise RuntimeError(f"GenAI is enabled but these settings are empty: {', '.join(missing)}")
        quotas = QuotaTracker(
            load_quotas(boto3.client("ssm", region_name=settings.region), settings.param_path)
        )
        gateway = BedrockGateway(
            boto3.client("bedrock-runtime", region_name=settings.region),
            settings.model_id,
            settings.guardrail_id,
            settings.guardrail_version,
        )
    return create_app(settings, gateway, quotas)

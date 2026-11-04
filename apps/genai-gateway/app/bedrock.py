"""Bedrock Converse call. Every request carries the guardrail; sources are grounding content."""

from dataclasses import dataclass
from typing import Any

SYSTEM_PROMPT = (
    "You explain marketing-mix model results to media planners. "
    "Use only the facts in the grounding sources. Cite every statement with the source id in "
    "square brackets, e.g. [S1]. Never invent numbers; if the sources do not answer the question, "
    "say so. Do not give financial or legal advice."
)


@dataclass(frozen=True)
class Source:
    id: str
    text: str


@dataclass(frozen=True)
class ModelAnswer:
    text: str
    intervened: bool
    input_tokens: int
    output_tokens: int


class BedrockGateway:
    """Thin wrapper so tests can replace the boto3 client."""

    def __init__(self, client: Any, model_id: str, guardrail_id: str, guardrail_version: str) -> None:
        self._client = client
        self._model_id = model_id
        self._guardrail_id = guardrail_id
        self._guardrail_version = guardrail_version

    def build_request(self, question: str, sources: list[Source], max_tokens: int) -> dict[str, Any]:
        grounding = "\n\n".join(f"[{s.id}]\n{s.text}" for s in sources)
        return {
            "modelId": self._model_id,
            "system": [{"text": SYSTEM_PROMPT}],
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"guardContent": {"text": {"text": grounding, "qualifiers": ["grounding_source"]}}},
                        {"guardContent": {"text": {"text": question, "qualifiers": ["query"]}}},
                    ],
                }
            ],
            "inferenceConfig": {"maxTokens": max_tokens, "temperature": 0},
            "guardrailConfig": {
                "guardrailIdentifier": self._guardrail_id,
                "guardrailVersion": self._guardrail_version,
                "trace": "enabled",
            },
        }

    def ask(self, question: str, sources: list[Source], max_tokens: int) -> ModelAnswer:
        response = self._client.converse(**self.build_request(question, sources, max_tokens))
        content = response.get("output", {}).get("message", {}).get("content", [])
        text = "".join(part.get("text", "") for part in content)
        usage = response.get("usage", {})
        return ModelAnswer(
            text=text,
            intervened=response.get("stopReason") == "guardrail_intervened",
            input_tokens=int(usage.get("inputTokens", 0)),
            output_tokens=int(usage.get("outputTokens", 0)),
        )

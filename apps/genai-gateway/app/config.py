"""Settings from the task definition (environment + SSM values injected by ECS)."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    environment: str
    region: str
    enabled: bool
    model_id: str
    guardrail_id: str
    guardrail_version: str
    param_path: str
    metrics_namespace: str

    @classmethod
    def from_env(cls) -> "Settings":
        env = os.environ.get("APP_ENV", "local")
        return cls(
            environment=env,
            region=os.environ.get("AWS_REGION", "us-east-1"),
            enabled=os.environ.get("GENAI_ENABLED", "false").strip().lower() == "true",
            model_id=os.environ.get("GENAI_MODEL_ID", ""),
            guardrail_id=os.environ.get("GENAI_GUARDRAIL_ID", ""),
            guardrail_version=os.environ.get("GENAI_GUARDRAIL_VERSION", ""),
            param_path=os.environ.get("GENAI_PARAM_PATH", f"/mmm/{env}/genai"),
            metrics_namespace=os.environ.get("METRICS_NAMESPACE", "MMM/GenAI"),
        )

    def missing(self) -> list[str]:
        """Settings that must be present before a model call is allowed."""
        required = {
            "GENAI_MODEL_ID": self.model_id,
            "GENAI_GUARDRAIL_ID": self.guardrail_id,
            "GENAI_GUARDRAIL_VERSION": self.guardrail_version,
        }
        return [name for name, value in required.items() if not value]

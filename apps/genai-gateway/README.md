# apps/genai-gateway

Reference GenAI gateway for Release 2 (Step 14): the only path from the platform to Amazon
Bedrock. The API calls it through Service Connect (`http://genai-gateway:8080`); it calls Bedrock
through the PrivateLink endpoint with the guardrail on every request. Guide and contract:
[docs/12](../../docs/12-genai-bedrock.md). The dev team owns it from here (features, prompts).

| Path | What |
|---|---|
| `app/main.py` | FastAPI: `GET /health`, `POST /v1/explain`; flag, quota, error mapping, metadata logging |
| `app/bedrock.py` | Converse request: system prompt, sources as `grounding_source`, question as `query`, `guardrailConfig` |
| `app/grounding.py` | Post-checks: citations must name supplied sources, numbers must appear in them |
| `app/usage.py` | Per-BU daily quotas from SSM, EMF metric `MMM/GenAI Tokens` |
| `app/config.py` | Settings from the task definition (SSM values injected by ECS) |

```powershell
uv sync --frozen
uv run ruff check .; uv run ruff format --check .; uv run mypy .
uv run pytest --cov            # CI gate: 80 %
```

Runs as UID 1000 on a read-only root filesystem; start command: `uvicorn --factory app.main:build`
(same in `ecs/<env>/genai-gateway.json`).

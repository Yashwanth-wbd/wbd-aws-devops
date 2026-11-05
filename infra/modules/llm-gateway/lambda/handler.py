"""LLM gateway proxy: one private API in front of the approved OpenAI, Anthropic and Google models.

Request path /<provider>/<rest of the provider path> is forwarded to that provider's API with the
key read from Secrets Manager ({"api_key": "..."}). Every prompt and every answer passes the
Bedrock guardrail (ApplyGuardrail): a blocked prompt returns 400, an answer the guardrail changes
is returned as {"guardrail": "INTERVENED", "output": "<text>"}. Prompt and answer text is never logged.
"""

import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PROVIDERS = json.loads(os.environ["PROVIDERS"])
GUARDRAIL_ID = os.environ["GUARDRAIL_ID"]
GUARDRAIL_VERSION = os.environ["GUARDRAIL_VERSION"]
TIMEOUT = int(os.environ.get("UPSTREAM_TIMEOUT_SECONDS", "28"))
MAX_BODY = int(os.environ.get("MAX_BODY_BYTES", "1048576"))

AUTH_HEADERS = {"bearer": "authorization", "x-api-key": "x-api-key", "x-goog-api-key": "x-goog-api-key"}
PASS_HEADERS = {"content-type", "anthropic-version", "anthropic-beta", "openai-beta"}
TEXT_KEYS = {"content", "text", "prompt", "system", "input"}

_secrets = boto3.client("secretsmanager")
_bedrock = boto3.client("bedrock-runtime")
_keys: dict[str, tuple[float, str]] = {}


def _api_key(provider: str) -> str:
    cached = _keys.get(provider)
    if cached and time.time() - cached[0] < 300:
        return cached[1]
    value = json.loads(_secrets.get_secret_value(SecretId=PROVIDERS[provider]["secret_arn"])["SecretString"])["api_key"]
    _keys[provider] = (time.time(), value)
    return value


def _texts(obj) -> list[str]:
    found: list[str] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and k in TEXT_KEYS:
                found.append(v)
            else:
                found.extend(_texts(v))
    elif isinstance(obj, list):
        for v in obj:
            found.extend(_texts(v))
    return found


def _guardrail(source: str, texts: list[str]) -> dict | None:
    texts = [t for t in texts if t.strip()]
    if not texts:
        return None
    result = _bedrock.apply_guardrail(
        guardrailIdentifier=GUARDRAIL_ID,
        guardrailVersion=GUARDRAIL_VERSION,
        source=source,
        content=[{"text": {"text": t}} for t in texts],
    )
    if result.get("action") == "GUARDRAIL_INTERVENED":
        return {"guardrail": "INTERVENED", "output": " ".join(o.get("text", "") for o in result.get("outputs", []))}
    return None


def _reply(status: int, body: dict | str, headers: dict | None = None) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json", **(headers or {})},
        "body": body if isinstance(body, str) else json.dumps(body),
    }


def lambda_handler(event, context):
    started = time.time()
    path = (event.get("pathParameters") or {}).get("proxy", "")
    provider, _, rest = path.partition("/")
    if provider not in PROVIDERS:
        return _reply(404, {"error": f"unknown provider '{provider}'", "providers": sorted(PROVIDERS)})

    raw = event.get("body") or ""
    if len(raw) > MAX_BODY:
        return _reply(413, {"error": "request too large"})
    try:
        request = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return _reply(400, {"error": "body must be JSON"})

    blocked = _guardrail("INPUT", _texts(request))
    if blocked:
        logger.info(json.dumps({"provider": provider, "path": rest, "status": 400, "guardrail": "input"}))
        return _reply(400, blocked)

    cfg = PROVIDERS[provider]
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items() if k.lower() in PASS_HEADERS}
    headers.setdefault("content-type", "application/json")
    auth = AUTH_HEADERS[cfg["auth"]]
    key = _api_key(provider)
    headers[auth] = f"Bearer {key}" if cfg["auth"] == "bearer" else key

    query = urllib.parse.urlencode(event.get("queryStringParameters") or {})
    url = f"{cfg['base_url'].rstrip('/')}/{rest}" + (f"?{query}" if query else "")
    req = urllib.request.Request(url, data=raw.encode() if raw else None, headers=headers, method=event.get("httpMethod", "POST"))
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:  # noqa: S310 - fixed https base URLs from Terraform
            status, payload = resp.status, resp.read().decode()
    except urllib.error.HTTPError as err:
        status, payload = err.code, err.read().decode()
    except (urllib.error.URLError, TimeoutError) as err:
        logger.warning(json.dumps({"provider": provider, "path": rest, "status": 504, "error": str(err)}))
        return _reply(504, {"error": f"{provider} did not answer in {TIMEOUT}s"})

    usage = None
    if status == 200:
        try:
            answer = json.loads(payload)
            usage = answer.get("usage") or answer.get("usageMetadata")
            changed = _guardrail("OUTPUT", _texts(answer.get("choices") or answer.get("content") or answer.get("candidates") or []))
            if changed:
                payload = json.dumps(changed)
        except json.JSONDecodeError:
            pass

    logger.info(json.dumps({"provider": provider, "path": rest, "status": status, "ms": int((time.time() - started) * 1000), "usage": usage}))
    return _reply(status, payload)

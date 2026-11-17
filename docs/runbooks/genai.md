# Runbook: GenAI (Release 2)

Guide and controls: [docs/12](../12-genai-bedrock.md). The API calls Amazon Bedrock directly
(Converse / InvokeModel through the `bedrock-runtime` VPC endpoint, task role, no API keys) with the
pinned Bedrock guardrail on every call (`guardrailConfig`; enforced by the IAM condition
`bedrock:GuardrailIdentifier`). Anthropic is the default model; OpenAI / Google optional in dev /
staging. Dashboard `mmm-<env>-genai`; alarms: `terraform output genai`.

## Turn GenAI off (users)

Use for: bad / unsafe answers, guardrail problem, cost spike, WBD request.

```bash
# 1. Emergency (minutes): flag off, restart the API so it stops calling Bedrock
aws ssm put-parameter --name /mmm/$E/genai_enabled --value false --overwrite
aws ecs update-service --cluster $P-ecs --service $P-api --force-new-deployment
# 2. Same day: PR genai_enabled = false in infra/environments/<env>/terraform.tfvars
#    (otherwise the next apply sets the old value again)
```

The API returns GenAI-unavailable when the flag is off.

## Turn GenAI on

Only with WBD approval: [docs/12 §3](../12-genai-bedrock.md#3-turning-it-on-per-environment-dev--staging--prod).
Bedrock model access for the models in `genai_model_ids`, `enable_genai = true` and
`genai_enabled = true` (PR → apply), then force a new deployment of `api`. Confirm the
`BEDROCK_*` variables are set on the API task and a test call through the app succeeds.

## Alarms

| Alarm | Meaning | Action |
|---|---|---|
| `bedrock-invocation-errors` | Client or server errors from Bedrock | `AccessDeniedException`: model access, `genai_model_ids`, guardrail ID / version in the request vs `genai/guardrail`, SCP / boundary regions (`genai_inference_regions`); server errors: AWS Health, retry; flag off if users are affected |
| `bedrock-throttles` | Bedrock tokens / requests per minute quota reached | Service Quotas for the model (raise), check `GenAITokens` per BU for misuse, lower `genai_token_quotas` |
| `bedrock-latency-p95` | Slow answers | Model / region load (AWS Health), prompt size, consider the cross-region inference profile |
| `genai-guardrail-interventions` | Unusual block rate | Guardrail trace in the app logs; misuse or a broken prompt |
| `genai-tokens-<bu>` | 80 % of the daily token quota of a BU | Review API logs (`business_unit`, user); raise quotas (PR) or keep 429s |

## Guardrail problems

- **Too many blocks:** find the filter in the guardrail trace (app logs, or invocation logs if enabled), adjust thresholds / bump `genai_guardrail_version_label` (PR, WBD approval), apply, redeploy the API.
- **Something harmful got through:** flag off first, keep log evidence, tighten the guardrail, re-test in staging, then flag on.
- **Roll back the guardrail:** set `genai_guardrail_version_label` back, apply (published versions are kept), redeploy the API.

## Network

If calls time out, check the `bedrock-runtime` VPC endpoint is `available` with private DNS
(`terraform output genai.bedrock_endpoint_id`), and the API security group allows 443 out. If calls
are denied, check the endpoint policy lists the model (`genai_model_ids`) and the API role policy
(`InvokeApprovedModelsWithGuardrail`).

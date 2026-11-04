# Runbook: GenAI (Release 2)

Guide and controls: [docs/12](../12-genai-bedrock.md). Gateway `mmm-<env>-genai-gateway`, logs
`/ecs/mmm-<env>/genai-gateway`, invocation logs `/aws/bedrock/mmm-<env>-invocations`, dashboard `mmm-<env>-genai`.

## Turn GenAI off (users)

Use for: bad / unsafe answers, guardrail problem, cost spike, WBD request.

```bash
# 1. Emergency (minutes): flag off, restart the readers
aws ssm put-parameter --name /mmm/$E/genai_enabled --value false --overwrite
for s in api genai-gateway; do aws ecs update-service --cluster $P-ecs --service $P-$s --force-new-deployment; done
# 2. Same day: PR genai_enabled = false in infra/environments/<env>/terraform.tfvars
#    (otherwise the next apply sets the old value again)
```

Stop all Bedrock traffic immediately (gateway down, API shows GenAI unavailable):
`aws ecs update-service --cluster $P-ecs --service $P-genai-gateway --desired-count 0`
(autoscaling sets the minimum again on the next apply – keep the flag off).

## Turn GenAI on

Only with WBD approval: [docs/12 §3](../12-genai-bedrock.md#3-turning-it-on-per-environment-dev--staging--prod).
`genai_enabled = true` (PR → apply) and force new deployments of `api` and `genai-gateway`.
Check `GET /health` on the gateway shows `genai_enabled: true` and the expected guardrail version.

## Alarms

| Alarm | Meaning | Action |
|---|---|---|
| `…-genai-<model>-server-errors` | Bedrock 5xx | AWS Health / Bedrock status; the gateway returns 502. If prolonged, flag off and tell users |
| `…-genai-<model>-client-errors` | 4xx: access denied, validation, model not enabled | `AccessDeniedException`: model access (console), endpoint policy, task role, SCP; `ValidationException`: gateway bug or model ID / guardrail version mismatch in SSM |
| `…-genai-<model>-throttles` | Over the account's Bedrock quota | Request a quota increase; lower `max_tokens`; temporary: lower per-BU quotas |
| `…-genai-<model>-latency-p95` | Model slow | Usually long prompts / outputs; check token counts; AWS Health |
| `…-genai-daily-tokens` / `…-daily-tokens-<bu>` | Daily token quota exceeded (all / one BU) | Check who (gateway log `business_unit`, `user`); a loop in the API? Agree with the BU owner; raise `genai_token_quotas` (PR) or keep the 429s |
| Budget `mmm-<env>-genai-monthly` email | Spend at 50 / 80 / 100 % or forecast over | Review usage per BU with WBD; flag off if unapproved overspend |

## Guardrail problems

- **Too many blocks** (users get the blocked message for normal questions): find the filter in
  the invocation log (`guardrail trace`), adjust the threshold / PII types (PR, WBD approval),
  bump `genai_guardrail_version_label`, apply, redeploy the gateway.
- **Something harmful got through:** flag off first, keep the invocation log entry (evidence),
  tighten the guardrail as above, re-test with the evaluation set in staging, then flag on.
- **Roll back the guardrail:** set `genai_guardrail_version_label` back (published versions are
  kept), apply, redeploy the gateway.

## Private-endpoint checks

`AccessDenied … DenyBedrockOutsidePrivateLink` in the gateway log means traffic is not going
through `mmm-<env>-vpce-bedrock-runtime`: check the endpoint is `available` with private DNS on
and the gateway SG allows 443 to the endpoints SG.

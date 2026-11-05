# Runbook: GenAI (Release 2)

Guide and controls: [docs/12](../12-genai-bedrock.md). Private API Gateway LLM gateway (SigV4 from
the API task only), Bedrock Guardrails (`ApplyGuardrail` on input and output), provider keys in
Secrets Manager `mmm/<env>/llm/<provider>`. Dashboard and alarms: `terraform output genai`.

## Turn GenAI off (users)

Use for: bad / unsafe answers, guardrail problem, cost spike, WBD request.

```bash
# 1. Emergency (minutes): flag off, restart the API so it stops calling the gateway
aws ssm put-parameter --name /mmm/$E/genai_enabled --value false --overwrite
aws ecs update-service --cluster $P-ecs --service $P-api --force-new-deployment
# 2. Same day: PR genai_enabled = false in infra/environments/<env>/terraform.tfvars
#    (otherwise the next apply sets the old value again)
```

The API returns GenAI-unavailable when the flag is off; the gateway remains but receives no traffic.

## Turn GenAI on

Only with WBD approval: [docs/12 §3](../12-genai-bedrock.md#3-turning-it-on-per-environment-dev--staging--prod).
Fill provider secrets out of band, set `enable_genai = true` and `genai_enabled = true` (PR → apply),
then force a new deployment of `api`. Confirm `LLM_GATEWAY_URL` is set on the API task and a test
call through the app succeeds with guardrail metadata.

## Alarms

| Alarm | Meaning | Action |
|---|---|---|
| Gateway / proxy Lambda errors | Provider or guardrail failure | Lambda log groups from `terraform output genai.log_groups`; flag off if unsafe |
| Guardrail alarm | Guardrail misconfiguration or throttling | Check guardrail id/version in Terraform; adjust thresholds with WBD approval |
| Per-provider / token quotas | Daily quota exceeded (SSM `genai_token_quotas`) | Review API logs (`business_unit`, user); raise quotas (PR) or keep 429s |

## Guardrail problems

- **Too many blocks:** find the filter in gateway logs, adjust `genai_guardrail_version_label` / thresholds (PR, WBD approval), apply.
- **Something harmful got through:** flag off first, keep log evidence, tighten guardrail, re-test in staging, then flag on.
- **Roll back the guardrail:** set `genai_guardrail_version_label` back, apply (published versions are kept).

## Network

The API task role is the only principal allowed to invoke the private API Gateway. If calls fail with
403 or timeout, check the `execute-api` VPC endpoint is `available`, the API security group allows
443 to the endpoints group, and `LLM_GATEWAY_URL` matches `terraform output genai.gateway_url`.

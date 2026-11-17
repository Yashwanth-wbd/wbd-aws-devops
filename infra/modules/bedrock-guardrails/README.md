# bedrock-guardrails

Bedrock guardrail applied by Amazon Bedrock to every prompt and answer. The API passes
`guardrailConfig` (ID + pinned version) on every Converse / InvokeModel call, whichever Bedrock
model serves it (Anthropic default; OpenAI / Google optional), and the API task role can only
invoke models with this guardrail (IAM condition `bedrock:GuardrailIdentifier`). `ApplyGuardrail`
is also allowed for checks outside a model call. Only with `enable_genai`.

**Status:** implemented (v6 architecture: Bedrock directly, no LLM gateway).

## What it creates

| Resource | Notes |
|---|---|
| `aws_bedrock_guardrail` `<prefix>-genai` | Prompt-attack filter on input (`prompt_attack_strength`), content filters (`content_filter_strength`), PII masking (`pii_anonymize_types`) and blocking (`pii_block_types`, incl. AWS keys and passwords), contextual grounding and relevance thresholds, fixed blocked messages. KMS (`genai`) |
| `aws_bedrock_guardrail_version` | Pinned version used by the API (SSM `genai/guardrail`, task env `BEDROCK_GUARDRAIL_VERSION`). Change `version_label` to publish a new one after a policy change |
| `aws_cloudwatch_metric_alarm` interventions | More than `intervention_alarm_threshold` blocks per 15 minutes → `alarm_topic_arn` |

## Inputs

`name_prefix`, `kms_key_arn`, `version_label` ("v1"), `prompt_attack_strength`,
`content_filter_strength`, `pii_anonymize_types`, `pii_block_types`, `grounding_threshold`,
`relevance_threshold`, `blocked_input_message`, `blocked_output_message`,
`intervention_alarm_threshold`, `alarm_topic_arn`, `tags`.

## Outputs

`guardrail_id`, `guardrail_arn`, `guardrail_version`, `alarm_name`.

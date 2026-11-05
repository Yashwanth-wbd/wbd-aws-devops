# bedrock-guardrails

Bedrock guardrail applied by the LLM gateway to every prompt and answer, whichever provider
answers (`ApplyGuardrail`). Only with `enable_genai`.

**Status:** implemented (v2 architecture).

## What it creates

| Resource | Notes |
|---|---|
| `aws_bedrock_guardrail` `<prefix>-genai` | Prompt-attack filter on input (`prompt_attack_strength`), content filters (`content_filter_strength`), PII masking (`pii_anonymize_types`) and blocking (`pii_block_types`, incl. AWS keys and passwords), contextual grounding and relevance thresholds, fixed blocked messages. KMS (`genai`) |
| `aws_bedrock_guardrail_version` | Pinned version used by the gateway. Change `version_label` to publish a new one after a policy change |
| `aws_cloudwatch_metric_alarm` interventions | More than `intervention_alarm_threshold` blocks per 15 minutes → `alarm_topic_arn` |

## Inputs

`name_prefix`, `kms_key_arn`, `version_label` ("v1"), `prompt_attack_strength`,
`content_filter_strength`, `pii_anonymize_types`, `pii_block_types`, `grounding_threshold`,
`relevance_threshold`, `blocked_input_message`, `blocked_output_message`,
`intervention_alarm_threshold`, `alarm_topic_arn`, `tags`.

## Outputs

`guardrail_id`, `guardrail_arn`, `guardrail_version`, `alarm_name`.

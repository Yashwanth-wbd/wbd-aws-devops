locals {
  tags = merge(var.tags, { Component = "genai" })
  name = "${var.name_prefix}-genai"
}

# Applied by the LLM gateway (ApplyGuardrail) to every prompt and every answer, whichever
# provider (OpenAI, Anthropic, Google) serves the call. The version is pinned.
resource "aws_bedrock_guardrail" "this" {
  name                      = local.name
  description               = "MMM GenAI guardrail: prompt attacks, harmful content, PII, contextual grounding."
  blocked_input_messaging   = var.blocked_input_message
  blocked_outputs_messaging = var.blocked_output_message
  kms_key_arn               = var.kms_key_arn

  content_policy_config {
    # Prompt-attack filtering applies to the input only; output strength must be NONE.
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = var.prompt_attack_strength
      output_strength = "NONE"
    }

    dynamic "filters_config" {
      for_each = toset(["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT"])

      content {
        type            = filters_config.value
        input_strength  = var.content_filter_strength
        output_strength = var.content_filter_strength
      }
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = toset(var.pii_anonymize_types)

      content {
        type   = pii_entities_config.value
        action = "ANONYMIZE"
      }
    }

    dynamic "pii_entities_config" {
      for_each = toset(var.pii_block_types)

      content {
        type   = pii_entities_config.value
        action = "BLOCK"
      }
    }
  }

  # Evaluated when the caller passes the MMM sources (grounding source + query) with the request.
  contextual_grounding_policy_config {
    filters_config {
      type      = "GROUNDING"
      threshold = var.grounding_threshold
    }

    filters_config {
      type      = "RELEVANCE"
      threshold = var.relevance_threshold
    }
  }

  word_policy_config {
    managed_word_lists_config {
      type = "PROFANITY"
    }
  }

  tags = merge(local.tags, { Name = local.name })
}

# Bump version_label (tfvars) to publish a new immutable version after a policy change.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "${var.name_prefix} ${var.version_label}"
  skip_destroy  = true

  lifecycle {
    replace_triggered_by = [terraform_data.version_label]
  }
}

resource "terraform_data" "version_label" {
  input = var.version_label
}

# ------------------------------------------------------------------ Alarm: unusual block rate
resource "aws_cloudwatch_metric_alarm" "interventions" {
  alarm_name          = "${local.name}-guardrail-interventions"
  alarm_description   = "Guardrail ${local.name} blocked more than ${var.intervention_alarm_threshold} requests/answers in 15 min - possible misuse or a broken prompt"
  namespace           = "AWS/Bedrock/Guardrails"
  metric_name         = "InvocationsIntervened"
  dimensions          = { GuardrailArn = aws_bedrock_guardrail.this.guardrail_arn, GuardrailVersion = aws_bedrock_guardrail_version.this.version }
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = var.intervention_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]

  tags = local.tags
}

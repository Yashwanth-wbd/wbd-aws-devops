data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  tags       = merge(var.tags, { Component = "genai" })

  # Cross-region inference profiles (us./eu./apac./global.) route to the base model in several
  # regions, so the profile ARN and the base model in every region must both be allowed.
  profile_pattern = "^(us|us-gov|eu|apac|global)\\."

  model_arns = flatten([
    for id in var.approved_model_ids : can(regex(local.profile_pattern, id)) ? [
      "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:inference-profile/${id}",
      "arn:${local.partition}:bedrock:*::foundation-model/${replace(id, "/${local.profile_pattern}/", "")}",
      ] : [
      "arn:${local.partition}:bedrock:${local.region}::foundation-model/${id}",
    ]
  ])

  bedrock_source_arn = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:*"
}

# ------------------------------------------------------------------ Guardrail
# Every gateway call passes this guardrail (guardrailConfig); the version is pinned, so a change
# to the policies below takes effect only when a new version is published and the SSM parameter moves.
resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name_prefix}-genai"
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

  # Answers must be supported by the MMM sources the gateway passes in (no invented numbers).
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

  tags = merge(local.tags, { Name = "${var.name_prefix}-genai" })
}

# Bump guardrail_version_label (tfvars) to publish a new immutable version after a policy change.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "${var.name_prefix} ${var.guardrail_version_label}"
  skip_destroy  = true

  lifecycle {
    replace_triggered_by = [terraform_data.guardrail_version_label]
  }
}

resource "terraform_data" "guardrail_version_label" {
  input = var.guardrail_version_label
}

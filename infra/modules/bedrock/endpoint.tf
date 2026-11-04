# ------------------------------------------------------------------ PrivateLink to Bedrock runtime
# Private DNS makes bedrock-runtime.<region>.amazonaws.com resolve to this endpoint inside the VPC;
# the policy lets only the gateway task role invoke the approved models with the guardrail.
data "aws_iam_policy_document" "endpoint" {
  statement {
    sid       = "InvokeApprovedModels"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = local.model_arns

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = var.invoker_role_arns
    }
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.this.guardrail_arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = var.invoker_role_arns
    }
  }
}

resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.endpoint_subnet_ids
  security_group_ids  = [var.endpoint_security_group_id]
  policy              = data.aws_iam_policy_document.endpoint.json

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-bedrock-runtime" })
}

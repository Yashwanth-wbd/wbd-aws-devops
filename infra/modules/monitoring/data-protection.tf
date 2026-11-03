# Masks secrets and card numbers in every log group of the account (audit findings are counted
# in CloudWatch; principals with logs:Unmask can still see the original values).
locals {
  data_identifier_arns = [for d in var.data_protection_identifiers : "arn:${local.partition}:dataprotection::aws:data-identifier/${d}"]
}

resource "aws_cloudwatch_log_account_policy" "data_protection" {
  count = var.enable_log_data_protection ? 1 : 0

  policy_name = "${var.name_prefix}-data-protection"
  policy_type = "DATA_PROTECTION_POLICY"
  scope       = "ALL"

  policy_document = jsonencode({
    Name    = "${var.name_prefix}-data-protection"
    Version = "2021-06-01"
    Statement = [
      {
        Sid            = "audit"
        DataIdentifier = local.data_identifier_arns
        Operation      = { Audit = { FindingsDestination = {} } }
      },
      {
        Sid            = "mask"
        DataIdentifier = local.data_identifier_arns
        Operation      = { Deidentify = { MaskConfig = {} } }
      },
    ]
  })
}

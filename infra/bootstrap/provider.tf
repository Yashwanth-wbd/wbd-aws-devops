provider "aws" {
  region = var.aws_region

  # Refuses to run if the current credentials belong to a different account, so the dev
  # tfvars can never be applied with staging or prod credentials.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

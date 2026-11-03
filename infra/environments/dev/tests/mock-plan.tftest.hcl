# Offline plan with mocked AWS providers: no account or credentials needed.
# Run by terraform.yml (static job) and scripts\mock-plan.ps1. Catches count/for_each values only
# known after apply, failing preconditions and tfvars errors; it does not check IAM, quotas or names.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["use1-az1", "use1-az2", "use1-az3", "use1-az4", "use1-az5", "use1-az6"], names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "aws" {
  alias = "us_east_1"
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-east-1", region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["use1-az1", "use1-az2", "use1-az3", "use1-az4", "use1-az5", "use1-az6"], names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
mock_provider "aws" {
  alias = "dr"
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root" }
  }
  mock_data "aws_region" {
    defaults = { name = "us-west-2", region = "us-west-2" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_availability_zones" {
    defaults = { zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3", "usw2-az4", "usw2-az5", "usw2-az6"], names = ["us-west-2a", "us-west-2b", "us-west-2c", "us-west-2d", "us-west-2e", "us-west-2f"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
run "plan" {
  command = plan
}

# Every optional feature on, so code paths behind the approval flags are planned too.
run "plan_all_features" {
  command = plan
  variables {
    enable_cross_region_copy   = true
    enable_vault_lock          = true
    enable_splunk_shipping     = true
    ship_vpc_flow_logs         = true
    enable_transit_gateway     = true
    enable_resolver_forwarding = true
    enable_application_signals = true
    enable_db_bootstrap        = true
    databricks_token_available = true

    enable_data_platform           = true
    databricks_self_assume_enabled = true
    enable_databricks_privatelink  = true
  }
}
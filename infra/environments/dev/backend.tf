# Values come from `terraform output backend_config` in infra/bootstrap (dev workspace).
# Backend blocks cannot use variables, so they are written out here.
terraform {
  backend "s3" {
    # add actual value
    bucket = "wbd-mmm-dev-tfstate-use1"
    key    = "environments/dev/terraform.tfstate"
    # add actual value
    region  = "us-east-1"
    encrypt = true
    # add actual value
    kms_key_id   = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
    use_lockfile = true
  }
}

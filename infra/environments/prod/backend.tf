# Values come from `terraform output backend_config` in infra/bootstrap (prod account, prod.tfvars).
# Backend blocks cannot use variables, so they are written out here.
terraform {
  backend "s3" {
    # add actual value
    bucket = "wbd-mmm-prd-tfstate-use1"
    key    = "environments/prod/terraform.tfstate"
    # add actual value
    region  = "us-east-1"
    encrypt = true
    # add actual value
    kms_key_id   = "arn:aws:kms:us-east-1:333333333333:key/00000000-0000-0000-0000-000000000000"
    use_lockfile = true
  }
}

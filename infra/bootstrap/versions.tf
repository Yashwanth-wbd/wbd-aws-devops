terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # No backend block: the bootstrap creates the remote state bucket, so its own state is
  # local. One workspace per account keeps the three local state files apart
  # (terraform.tfstate.d/<workspace>/terraform.tfstate).
}

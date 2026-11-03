terraform {
  # 1.10+ is needed for S3-native state locking (use_lockfile in backend.tf).
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # zips the data-trigger Lambda (Step 13)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

# CloudFront-scope WAF, its logs and the CloudFront certificate live in us-east-1.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

# DR region for AWS Backup cross-region copies (used only when enable_cross_region_copy = true).
provider "aws" {
  alias               = "dr"
  region              = var.dr_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.tags
  }
}

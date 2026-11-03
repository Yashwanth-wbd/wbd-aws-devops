# ================================================================== Step 8 - Edge (CloudFront + WAF)
module "edge" {
  source = "../../modules/edge"
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix     = local.name_prefix
  aliases         = var.cloudfront_aliases
  certificate_arn = var.cloudfront_certificate_arn
  okta_issuer     = var.okta_issuer

  frontend_bucket_regional_domain_name = module.buckets["frontend"].bucket_regional_domain_name
  alb_origin_domain_name               = var.alb_origin_domain_name
  origin_verify_value                  = module.secrets.generated_values["edge/origin-verify"]

  price_class         = var.cloudfront_price_class
  geo_allow_countries = var.geo_allow_countries
  waf_rate_limit      = var.waf_rate_limit

  access_log_bucket_domain_name = module.log_bucket.bucket_domain_name
  access_log_prefix             = module.log_bucket.prefixes.cloudfront

  # The stack's logs key works only when the stack itself is in us-east-1.
  create_waf_log_kms_key = var.aws_region != "us-east-1"
  waf_log_kms_key_arn    = var.aws_region == "us-east-1" ? module.kms.key_arns["logs"] : null
}

# Frontend bucket: readable only by this distribution (bucket policy of module.buckets["frontend"]).
data "aws_iam_policy_document" "frontend_oac" {
  statement {
    sid       = "CloudFrontReadsFrontend"
    actions   = ["s3:GetObject"]
    resources = ["arn:${local.partition}:s3:::wbd-mmm-${local.env_short}-frontend-${local.region_code}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.edge.distribution_arn]
    }
  }
}

# The S3 key policy cannot name the distribution (the key is created first), so it allows this
# account's distributions; the bucket policy above limits reads to this one.
data "aws_iam_policy_document" "s3_key_cloudfront" {
  #checkov:skip=CKV_AWS_109:Key policy; "*" means this key only.
  #checkov:skip=CKV_AWS_111:Key policy; "*" means this key only.
  #checkov:skip=CKV_AWS_356:Key policy; "*" means this key only.
  statement {
    sid       = "CloudFrontDecryptsFrontend"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = ["arn:${local.partition}:cloudfront::${local.account_id}:distribution/*"]
    }
  }
}

# Placeholder page so the whole path can be tested before the first frontend deploy (Step 11).
resource "aws_s3_object" "frontend_seed" {
  bucket                 = module.buckets["frontend"].bucket_name
  key                    = "releases/seed/index.html"
  content_type           = "text/html"
  server_side_encryption = "aws:kms"
  kms_key_id             = module.kms.key_arns["s3"]
  content                = "<!doctype html><html><head><title>MMM ${var.environment}</title></head><body><p>MMM ${var.environment}: edge is up, waiting for the first frontend deploy.</p></body></html>"
}

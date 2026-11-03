locals {
  tags = merge(var.tags, { Component = "edge" })

  okta_origin = regex("^https://[^/]+", var.okta_issuer)

  default_csp = join("; ", [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "font-src 'self' data:",
    "connect-src 'self' ${local.okta_origin}",
    "frame-src ${local.okta_origin}",
    "form-action 'self' ${local.okta_origin}",
    "object-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
  ])
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Forwards every viewer header except Host (incl. Authorization, since caching is disabled).
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ------------------------------------------------------------------ Frontend origin (S3 through OAC)
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name_prefix}-frontend"
  description                       = "CloudFront reads the frontend bucket with SigV4"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# current_release is changed by frontend-ci.yml, never by Terraform after creation.
resource "aws_cloudfront_key_value_store" "frontend" {
  name    = "${var.name_prefix}-frontend"
  comment = "Frontend release pointer (current_release)"
}

resource "aws_cloudfrontkeyvaluestore_key" "current_release" {
  key_value_store_arn = aws_cloudfront_key_value_store.frontend.arn
  key                 = "current_release"
  value               = var.initial_release

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_cloudfront_function" "frontend_router" {
  name    = "${var.name_prefix}-frontend-router"
  runtime = "cloudfront-js-2.0"
  comment = "Serves the current release folder and index.html for app routes"
  publish = true
  code = templatefile("${path.module}/functions/frontend-router.js", {
    kvs_id          = element(split("/", aws_cloudfront_key_value_store.frontend.arn), 1)
    initial_release = var.initial_release
  })

  key_value_store_associations = [aws_cloudfront_key_value_store.frontend.arn]
}

# ------------------------------------------------------------------ Security headers (both behaviours)
resource "aws_cloudfront_response_headers_policy" "security" {
  #checkov:skip=CKV_AWS_259:HSTS is 2 years with includeSubDomains; preload commits the whole WBD domain and is the domain owners' decision.
  name    = "${var.name_prefix}-security-headers"
  comment = "HSTS, CSP, frame, content-type and referrer headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }

    content_security_policy {
      content_security_policy = coalesce(var.content_security_policy, local.default_csp)
      override                = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    xss_protection {
      protection = true
      mode_block = true
      override   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=()"
      override = true
    }
  }
}

# ------------------------------------------------------------------ Distribution
resource "aws_cloudfront_distribution" "this" {
  #checkov:skip=CKV_AWS_310:Origin failover needs a second region; DR is handled in Step 10.
  #checkov:skip=CKV_AWS_374:Geo restriction is a WBD business decision (geo_allow_countries; empty = none).
  #checkov:skip=CKV2_AWS_47:The web ACL includes AWSManagedRulesKnownBadInputsRuleSet (Log4j) through a dynamic block Checkov cannot read.
  enabled             = true
  comment             = "${var.name_prefix} MMM app"
  aliases             = var.aliases
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = var.price_class
  web_acl_id          = aws_wafv2_web_acl.this.arn

  origin {
    origin_id                = "frontend"
    domain_name              = var.frontend_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "api"
    domain_name = var.alb_origin_domain_name

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = var.origin_read_timeout
      origin_keepalive_timeout = 5
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_value
    }
  }

  default_cache_behavior {
    target_origin_id           = "frontend"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.frontend_router.arn
    }
  }

  ordered_cache_behavior {
    path_pattern               = var.api_path_pattern
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = length(var.geo_allow_countries) > 0 ? "whitelist" : "none"
      locations        = var.geo_allow_countries
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = var.access_log_bucket_domain_name
    prefix          = "${var.access_log_prefix}/"
    include_cookies = false
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-cdn" })
}

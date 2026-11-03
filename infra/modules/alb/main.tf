locals {
  tags = merge(var.tags, { Component = "alb" })
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:Deletion protection is set per environment (on in prod).
  #checkov:skip=CKV2_AWS_28:WAF is attached to CloudFront (Step 8); the ALB only accepts CloudFront origin-facing IPs plus the X-Origin-Verify header.
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [var.security_group_id]
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
  enable_deletion_protection = var.deletion_protection
  idle_timeout               = var.idle_timeout

  access_logs {
    bucket  = var.access_log_bucket
    prefix  = var.access_log_prefix
    enabled = true
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "api" {
  #checkov:skip=CKV_AWS_378:TLS ends at the ALB; ALB -> task traffic stays in the VPC and is limited to the ALB security group.
  name                 = "${var.name_prefix}-api-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-api-tg" })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  # Anything without the CloudFront header is refused.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  tags = local.tags
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = local.tags
}

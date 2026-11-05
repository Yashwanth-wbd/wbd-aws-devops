locals {
  tags = merge(var.tags, { Component = "alb" })

  target_groups = {
    ui  = { port = var.ui_port, health_check_path = var.ui_health_check_path }
    api = { port = var.app_port, health_check_path = var.health_check_path }
  }

  auth = var.cognito == null ? [] : [var.cognito]
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:Deletion protection is set per environment (on in prod).
  #checkov:skip=CKV2_AWS_28:The regional WAF is associated by the waf-regional module (aws_wafv2_web_acl_association).
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

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:TLS ends at the ALB; ALB -> task traffic stays in the VPC and is limited to the ALB security group.
  for_each = local.target_groups

  name                 = "${var.name_prefix}-${each.key}-tg"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-${each.key}-tg" })
}

# ------------------------------------------------------------------ Listeners
resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:Port 80 only redirects to HTTPS.
  #checkov:skip=CKV_AWS_103:Port 80 only redirects to HTTPS; TLS policy applies to the 443 listener.
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

# Everything that is not /api/* is the UI; a browser without a session is sent to Cognito (WBD SSO).
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  dynamic "default_action" {
    for_each = local.auth

    content {
      type  = "authenticate-cognito"
      order = 1

      authenticate_cognito {
        user_pool_arn              = default_action.value.user_pool_arn
        user_pool_client_id        = default_action.value.client_id
        user_pool_domain           = default_action.value.domain_prefix
        on_unauthenticated_request = "authenticate"
        scope                      = "openid email profile"
        session_cookie_name        = "mmm-session"
        session_timeout            = default_action.value.session_seconds
      }
    }
  }

  default_action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.this["ui"].arn
  }

  tags = local.tags
}

# Health endpoint without login: target health checks, smoke test and uptime probes.
resource "aws_lb_listener_rule" "api_health" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    path_pattern {
      values = [var.health_check_path]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["api"].arn
  }

  tags = local.tags
}

# API calls need the session cookie; without it the ALB answers 401 (no redirect for XHR calls).
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  dynamic "action" {
    for_each = local.auth

    content {
      type  = "authenticate-cognito"
      order = 1

      authenticate_cognito {
        user_pool_arn              = action.value.user_pool_arn
        user_pool_client_id        = action.value.client_id
        user_pool_domain           = action.value.domain_prefix
        on_unauthenticated_request = "deny"
        scope                      = "openid email profile"
        session_cookie_name        = "mmm-session"
        session_timeout            = action.value.session_seconds
      }
    }
  }

  action {
    type             = "forward"
    order            = 2
    target_group_arn = aws_lb_target_group.this["api"].arn
  }

  tags = local.tags
}

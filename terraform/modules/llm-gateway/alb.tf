# Moved out of terraform/environments/dev/alb.tf.

resource "aws_lb" "gateway" {
  name = "ai-gateway-advisor-chat"
  # Public by design - this is the demo's own internet-reachable HTTPS
  # endpoint, not an accidental exposure.
  # trivy:ignore:AWS-0053
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  # Drops invalid headers (trivy AWS-0052).
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "gateway" {
  name        = "ai-gateway-advisor-chat"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health/liveliness"
    matcher             = "200-499" # lenient: proves reachability, not full LiteLLM health semantics
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "gateway_https" {
  load_balancer_arn = aws_lb.gateway.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

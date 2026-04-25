###############################################################################
# Application Load Balancer.
#
# - Lives in the public subnets. The internet hits it; it forwards to
#   targets in the private app subnets.
# - One target group on the app port; ASG attaches/detaches instances
#   automatically.
# - Health check is /health. The Flask app exposes it.
###############################################################################

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Don't yank the LB on a name change; let it drain.
  enable_deletion_protection = false

  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # Stable target group identity if attributes that force replacement change.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

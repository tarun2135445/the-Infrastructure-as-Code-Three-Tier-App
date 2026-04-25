###############################################################################
# Launch template + Auto Scaling Group.
#
# - AMI: latest Amazon Linux 2023 from the official SSM parameter. Refresh
#   instances when the AMI changes by triggering an instance refresh.
# - IMDSv2 required (http_tokens = "required") — best-practice; blocks SSRF
#   credential theft.
# - Root volume: gp3, encrypted by default.
# - Instance refresh runs on launch template version change.
###############################################################################

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "app" {
  name_prefix            = "${local.name_prefix}-app-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 8
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  # Render the user-data with the live RDS endpoint and secret ARN.
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    app_port   = var.app_port
    db_host    = aws_db_instance.app.address
    db_port    = aws_db_instance.app.port
    db_name    = var.db_name
    secret_arn = aws_secretsmanager_secret.db.arn
    region     = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-app"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-app"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name_prefix}-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = aws_subnet.private_app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  default_cooldown          = 60

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # launch_template changes always trigger an instance refresh — that's why
  # there's no `triggers` block here. Add e.g. `triggers = ["tag"]` if you
  # want tag-only changes to roll the fleet too.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  # Tags via a propagating list — ASG-tag API is its own dialect.
  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }

  # If the LT is replaced, ASG can re-bind to the new one.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${local.name_prefix}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50
  }
}

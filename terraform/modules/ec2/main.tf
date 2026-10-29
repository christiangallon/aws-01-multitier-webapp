###############################################################################
# Compute tier
#
#   Internet -> public ALB :80 -> web ASG (nginx :80, public subnets)
#            -> internal ALB :3000 -> app ASG (Node.js :3000, private subnets)
#
# Launch templates enforce IMDSv2, encrypted gp3 root volumes, detailed
# monitoring and embed a CloudWatch agent configuration in user data.
# Changing user data (e.g. a new app bundle hash) creates a new launch template
# version, which triggers a rolling ASG instance refresh.
###############################################################################

# Latest Amazon Linux 2023 AMI, resolved from the public SSM parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023.value)

  web_user_data = templatefile("${path.module}/user_data/web_userdata.sh", {
    aws_region           = var.aws_region
    environment          = var.environment
    app_alb_dns          = aws_lb.internal.dns_name
    app_port             = var.app_port
    static_assets_bucket = var.static_assets_bucket
    static_version       = var.static_version
    web_log_group_name   = var.web_log_group_name
  })

  app_user_data = templatefile("${path.module}/user_data/app_userdata.sh", {
    aws_region         = var.aws_region
    environment        = var.environment
    app_port           = var.app_port
    artifacts_bucket   = var.artifacts_bucket
    app_bundle_key     = var.app_bundle_key
    app_bundle_version = var.app_bundle_version
    db_host            = var.db_host
    db_port            = var.db_port
    db_name            = var.db_name
    db_secret_arn      = var.db_secret_arn
    app_log_group_name = var.app_log_group_name
  })
}

###############################################################################
# Public (internet-facing) ALB -> web tier
###############################################################################

resource "aws_lb" "public" {
  name               = substr("${var.name_prefix}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  idle_timeout               = 60
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "alb"
      enabled = true
    }
  }

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name                 = substr("${var.name_prefix}-web-tg", 0, 32)
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name_prefix}-web-tg"
  }
}

resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

###############################################################################
# Internal ALB -> app tier
###############################################################################

resource "aws_lb" "internal" {
  name               = substr("${var.name_prefix}-int-alb", 0, 32)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.internal_alb_sg_id]
  subnets            = var.private_subnet_ids

  idle_timeout               = 60
  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = {
    Name = "${var.name_prefix}-int-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name                 = substr("${var.name_prefix}-app-tg", 0, 32)
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name_prefix}-app-tg"
  }
}

resource "aws_lb_listener" "internal_app" {
  load_balancer_arn = aws_lb.internal.arn
  port              = var.app_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

###############################################################################
# Launch templates
###############################################################################

resource "aws_launch_template" "web" {
  name_prefix   = "${var.name_prefix}-web-"
  description   = "nginx web tier"
  image_id      = local.ami_id
  instance_type = var.web_instance_type
  user_data     = base64encode(local.web_user_data)

  vpc_security_group_ids = [var.web_sg_id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-web"
      Tier = "web"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.name_prefix}-web-root"
      Tier = "web"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.name_prefix}-app-"
  description   = "Node.js application tier"
  image_id      = local.ami_id
  instance_type = var.app_instance_type
  user_data     = base64encode(local.app_user_data)

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-app"
      Tier = "app"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.name_prefix}-app-root"
      Tier = "app"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Auto Scaling groups
###############################################################################

resource "aws_autoscaling_group" "web" {
  name                = "${var.name_prefix}-web-asg"
  min_size            = var.web_min_size
  max_size            = var.web_max_size
  desired_capacity    = var.web_desired
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns   = [aws_lb_target_group.web.arn]

  # EC2 health only: the web /health check proxies to the app tier, so an app
  # outage must not cause the healthy nginx fleet to be recycled.
  health_check_type         = "EC2"
  health_check_grace_period = 300
  default_instance_warmup   = 120

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTotalInstances",
  ]

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Tier"
    value               = "web"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.name_prefix}-app-asg"
  min_size            = var.app_min_size
  max_size            = var.app_max_size
  desired_capacity    = var.app_desired
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 600
  default_instance_warmup   = 180

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTotalInstances",
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 180
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Tier"
    value               = "app"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  depends_on = [aws_lb_listener.internal_app]
}

# Target-tracking scaling keeps average CPU around the target value.
resource "aws_autoscaling_policy" "web_cpu" {
  name                   = "${var.name_prefix}-web-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

resource "aws_autoscaling_policy" "app_cpu" {
  name                   = "${var.name_prefix}-app-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

###############################################################################
# Optional bastion host (SSM Session Manager is the recommended access path)
###############################################################################

resource "aws_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.bastion_sg_id]
  key_name               = var.bastion_key_name != "" ? var.bastion_key_name : null
  iam_instance_profile   = var.instance_profile_name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name_prefix}-bastion"
    Tier = "bastion"
  }

  lifecycle {
    precondition {
      condition     = var.bastion_key_name != ""
      error_message = "bastion_key_name must be set when enable_bastion = true."
    }
  }
}

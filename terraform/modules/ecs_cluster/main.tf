# One cluster, one ALB, one Service Connect namespace for the whole backend. Only the gateway is behind the ALB;
# every service is reachable only from other tasks of the cluster (security group below), by its short name.

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled" # avoid the extra CloudWatch charges for a low-traffic backend
  }
}

resource "aws_service_discovery_http_namespace" "this" {
  name = var.namespace_name
}

# --- Networking ---------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Shared by every task. Services accept traffic only from tasks in this group (the gateway and each other, e.g.
# sales -> inventory) and the gateway also from the ALB. Egress is open: tasks have public IPs (no NAT) and reach
# Neon, Upstash, SNS and SQS over the internet.
resource "aws_security_group" "tasks" {
  name_prefix = "${var.name}-tasks-"
  vpc_id      = var.vpc_id

  ingress {
    description = "service to service"
    from_port   = var.service_port
    to_port     = var.service_port
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "ALB to gateway"
    from_port       = var.gateway_port
    to_port         = var.gateway_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Load balancer -> gateway -------------------------------------------

resource "aws_lb" "this" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "gateway" {
  name        = "${var.name}-gateway"
  port        = var.gateway_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.gateway_health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
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
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 14
}

# --- IAM -------------------------------------------------------------

data "aws_iam_policy_document" "ecs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.role_prefix}-${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy covers ECR pull + log push, not reading the SSM secrets of the task definition.
data "aws_iam_policy_document" "read_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters"]
    resources = values(var.secrets)
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  count  = length(var.secrets) > 0 ? 1 : 0
  name   = "${var.name}-read-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.role_prefix}-${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

resource "aws_iam_role_policy" "task" {
  count  = var.attach_task_policy ? 1 : 0
  name   = "${var.name}-task-permissions"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_json
}

# --- Task definition + service -------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    merge(
      {
        name      = var.name
        image     = "${var.ecr_repository_url}:${var.image_tag}"
        essential = true
        portMappings = [
          {
            name          = "http"
            containerPort = var.container_port
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]
        environment = [for k, v in var.environment : { name = k, value = v }]
        secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.this.name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = "ecs"
          }
        }
      },
      var.health_check_command == null ? {} : {
        healthCheck = {
          command     = ["CMD-SHELL", var.health_check_command]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 90 # migrations run at start
        }
      }
    )
  ])

  # The service ignores its own task_definition (below), so CI's deploys are not reverted by `apply`. CI reads the
  # latest revision, so it inherits env/secret changes made here and overwrites only the image.
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = true # no NAT: egress to Neon, Upstash and AWS APIs goes out directly
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.namespace_arn

    dynamic "service" {
      for_each = var.expose_in_namespace ? [1] : []
      content {
        port_name      = "http"
        discovery_name = var.name

        client_alias {
          port     = var.container_port
          dns_name = var.name
        }
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "service-connect"
      }
    }
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

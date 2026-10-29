# SapoClone v2 Microservices Topology (8 services: platform, catalog, inventory,
# sales, customer, finance, integration, insight).
# Internal services are registered in ECS Service Connect and have no public ALB.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  microservices = {
    platform = {
      port        = 3000
      schema      = "platform"
      is_producer = true
      is_consumer = false
    }
    catalog = {
      port        = 3001
      schema      = "catalog"
      is_producer = true
      is_consumer = true
    }
    inventory = {
      port        = 3002
      schema      = "inventory"
      is_producer = true
      is_consumer = true
    }
    sales = {
      port        = 3003
      schema      = "sales"
      is_producer = true
      is_consumer = true
    }
    customer = {
      port        = 3004
      schema      = "customer"
      is_producer = true
      is_consumer = true
    }
    finance = {
      port        = 3005
      schema      = "finance"
      is_producer = true
      is_consumer = true
    }
    integration = {
      port        = 3006
      schema      = "integration"
      is_producer = true
      is_consumer = true
    }
    insight = {
      port        = 3007
      schema      = "insight"
      is_producer = false
      is_consumer = true
    }
  }

  enabled_microservices = var.enable_microservices_topology ? local.microservices : {}
}

module "microservice_ecr" {
  source   = "./modules/ecr_repository"
  for_each = local.enabled_microservices

  name = "pbl-${each.key}"
}

resource "aws_service_discovery_http_namespace" "internal" {
  count       = var.enable_microservices_topology ? 1 : 0
  name        = "pbl.internal"
  description = "ECS Service Connect internal namespace for SapoClone v2 microservices"
}

resource "aws_security_group" "microservices_internal" {
  count       = var.enable_microservices_topology ? 1 : 0
  name        = "pbl-microservices-internal-sg"
  description = "Internal-only traffic between KrakenD gateway and SapoClone v2 microservices"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Internal East-West HTTP and gateway traffic within microservices security group"
    from_port   = 3000
    to_port     = 3007
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "microservice" {
  for_each = local.enabled_microservices

  name              = "/ecs/pbl-${each.key}"
  retention_in_days = 7
}

resource "aws_iam_role" "microservice_execution" {
  for_each = local.enabled_microservices

  name = "pbl-${each.key}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "microservice_execution_managed" {
  for_each = local.enabled_microservices

  role       = aws_iam_role.microservice_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "microservice_execution_ssm" {
  for_each = local.enabled_microservices

  name = "ssm-secrets-read"
  role = aws_iam_role.microservice_execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "kms:Decrypt"]
      Resource = concat(values(aws_ssm_parameter.pbl_api)[*].arn, [aws_kms_key.ssm.arn])
    }]
  })
}

resource "aws_iam_role" "microservice_task" {
  for_each = local.enabled_microservices

  name = "pbl-${each.key}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "microservice_task_messaging" {
  for_each = local.enabled_microservices

  name = "least-privilege-messaging"
  role = aws_iam_role.microservice_task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      each.value.is_producer ? [
        {
          Sid      = "PublishOwnServiceEventsTopic"
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = [aws_sns_topic.service_events[each.key].arn]
        }
      ] : [],
      each.value.is_consumer ? [
        {
          Sid    = "ConsumeOwnServiceEventsQueue"
          Effect = "Allow"
          Action = [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "sqs:ChangeMessageVisibility"
          ]
          Resource = [module.service_event_queues[each.key].arn]
        }
      ] : []
    )
  })
}

resource "aws_ecs_task_definition" "microservice" {
  for_each = local.enabled_microservices

  family                   = "pbl-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.microservice_cpu
  memory                   = var.microservice_memory
  execution_role_arn       = aws_iam_role.microservice_execution[each.key].arn
  task_role_arn            = aws_iam_role.microservice_task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${module.microservice_ecr[each.key].url}:${var.pbl_api_bootstrap_image_tag}"
      essential = true

      portMappings = [
        {
          name          = "${each.key}-http"
          containerPort = each.value.port
          hostPort      = each.value.port
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      environment = concat(
        [
          { name = "NODE_ENV", value = "production" },
          { name = "SERVICE_NAME", value = each.key },
          { name = "PORT", value = tostring(each.value.port) },
          { name = "DATABASE_SCHEMA", value = each.value.schema },
          { name = "DATABASE_HOST", value = var.database_host },
          { name = "DATABASE_PORT", value = "5432" },
          { name = "DATABASE_USERNAME", value = "${each.value.schema}_app" },
          { name = "DATABASE_NAME", value = var.database_name },
          { name = "DATABASE_SSL_ENABLED", value = "true" },
          { name = "REDIS_HOST", value = var.redis_host },
          { name = "REDIS_PORT", value = tostring(var.redis_port) },
          { name = "REDIS_TLS", value = "true" },
          { name = "AWS_REGION", value = var.aws_region },
          { name = "AUTH_JWKS_URL", value = "http://platform.pbl.internal:3000/.well-known/jwks.json" },
          { name = "INVENTORY_INTERNAL_URL", value = "http://inventory.pbl.internal:3002" },
          {
            name  = "SNS_TOPIC_ARN_PREFIX"
            value = "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:pbl"
          }
        ],
        each.value.is_consumer ? [
          {
            name  = "SQS_QUEUE_URL"
            value = module.service_event_queues[each.key].url
          }
        ] : []
      )

      secrets = [
        {
          name      = "DATABASE_PASSWORD"
          valueFrom = aws_ssm_parameter.pbl_api["DATABASE_PASSWORD"].arn
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = aws_ssm_parameter.pbl_api["REDIS_PASSWORD"].arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.microservice[each.key].name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "microservice" {
  for_each = local.enabled_microservices

  name            = "pbl-${each.key}"
  cluster         = module.pbl_api.cluster_name
  task_definition = aws_ecs_task_definition.microservice[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.microservices_internal[0].id]
    assign_public_ip = true
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal[0].arn

    service {
      port_name      = "${each.key}-http"
      discovery_name = each.key

      client_alias {
        port     = each.value.port
        dns_name = "${each.key}.pbl.internal"
      }
    }
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# The whole backend: eight services and the gateway on one ECS cluster. Only the gateway sits behind the ALB.
# Services find each other by name through ECS Service Connect (http://sales:3000), the same names as in
# pbl-api's docker-compose.yml and krakend.json, so the production gateway config keeps the local hosts.

locals {
  topology = jsondecode(file("${path.module}/events-topology.json"))

  # Sizes are a starting point (256 CPU = 0.25 vCPU). Watch memory on sales and insight first.
  services = {
    platform    = { cpu = 256, memory = 512 }
    catalog     = { cpu = 256, memory = 512 }
    customer    = { cpu = 256, memory = 512 }
    inventory   = { cpu = 256, memory = 512 }
    sales       = { cpu = 512, memory = 1024 }
    finance     = { cpu = 256, memory = 512 }
    integration = { cpu = 256, memory = 512 }
    insight     = { cpu = 512, memory = 1024 }
  }

  service_port = 3000
  jwks_url     = "http://platform:${local.service_port}/.well-known/jwks.json"

  # Postgres role and schema of each service: see scripts/neon-bootstrap.sql. Platform's hand-written migrations
  # create their tables in `public` whatever DATABASE_SCHEMA says, so platform runs on `public`.
  database_user = { for name in keys(local.services) : name => "pbl_${name}" }
  database_schema = {
    for name in keys(local.services) : name => (name == "platform" ? null : name)
  }

  common_environment = {
    NODE_ENV                     = "production"
    PORT                         = tostring(local.service_port)
    AWS_REGION                   = var.aws_region
    APP_SWAGGER_ENABLED          = "false"
    DATABASE_HOST                = var.database_host
    DATABASE_PORT                = "5432"
    DATABASE_NAME                = var.database_name
    DATABASE_SSL_ENABLED         = "true"
    DATABASE_REJECT_UNAUTHORIZED = "true"
    DATABASE_MAX_CONNECTIONS     = "10"
    REDIS_HOST                   = var.redis_host
    REDIS_PORT                   = tostring(var.redis_port)
    REDIS_TLS_ENABLED            = "true"
    EVENTS_TRANSPORT             = "sns"
  }

  platform_environment = {
    APP_NAME                            = "platform"
    APP_DEBUG                           = "false"
    API_PREFIX                          = "api"
    APP_FALLBACK_LANGUAGE               = "en"
    APP_LOG_LEVEL                       = "warn"
    APP_LOG_SERVICE                     = "console"
    APP_CORS_ORIGIN                     = "false" # the gateway answers CORS
    APP_SWAGGER_ENABLED                 = "true"
    APP_URL                             = "https://api.${var.domain_name}/platform"
    DATABASE_TYPE                       = "postgres"
    DATABASE_LOGGING                    = "false"
    DATABASE_SYNCHRONIZE                = "false"
    SQS_QUEUE_URL                       = module.email_verification_queue.url
    AWS_S3_BUCKET                       = aws_s3_bucket.images.id
    AWS_S3_REGION                       = var.aws_region
    CDN_URL                             = "https://static.${var.domain_name}"
    AUTH_JWT_TOKEN_EXPIRES_IN           = "1d"
    AUTH_REFRESH_TOKEN_EXPIRES_IN       = "30d"
    AUTH_FORGOT_TOKEN_EXPIRES_IN        = "7d"
    AUTH_CONFIRM_EMAIL_TOKEN_EXPIRES_IN = "1d"
    AUTH_JWT_KEY_ID                     = "prod-1"
    AUTH_JWT_ISSUER                     = "platform"
    AUTH_JWT_AUDIENCE                   = "pbl6"
  }

  service_environment = {
    sales       = { INVENTORY_URL = "http://inventory:${local.service_port}" }
    integration = { SALES_SERVICE_URL = "http://sales:${local.service_port}" }
  }

  # SSM parameter ARNs by env var name
  platform_secret_arns = {
    AUTH_JWT_PRIVATE_KEY      = aws_ssm_parameter.platform["AUTH_JWT_PRIVATE_KEY"].arn
    AUTH_FORGOT_SECRET        = aws_ssm_parameter.platform["AUTH_FORGOT_SECRET"].arn
    AUTH_CONFIRM_EMAIL_SECRET = aws_ssm_parameter.platform["AUTH_CONFIRM_EMAIL_SECRET"].arn
    OBSERVE_APP_KEY           = aws_ssm_parameter.platform["OBSERVE_APP_KEY"].arn
    OBSERVE_APP_SECRET        = aws_ssm_parameter.platform["OBSERVE_APP_SECRET"].arn
    APP_SWAGGER_USER          = aws_ssm_parameter.platform["APP_SWAGGER_USER"].arn
    APP_SWAGGER_PASSWORD      = aws_ssm_parameter.platform["APP_SWAGGER_PASSWORD"].arn
  }

  service_secrets = {
    for name in keys(local.services) : name => merge(
      {
        DATABASE_PASSWORD  = aws_ssm_parameter.database[name].arn
        REDIS_PASSWORD     = aws_ssm_parameter.shared["REDIS_PASSWORD"].arn
        INTERNAL_S2S_TOKEN = aws_ssm_parameter.shared["INTERNAL_S2S_TOKEN"].arn
      },
      name == "platform" ? local.platform_secret_arns : {},
      name == "integration" ? { INTEGRATION_CREDENTIAL_MASTER_KEY = aws_ssm_parameter.integration_master_key.arn } : {},
    )
  }
}

# --- Cluster, load balancer, namespace -------------------------------------

module "cluster" {
  source = "./modules/ecs_cluster"

  name            = "pbl"
  vpc_id          = data.aws_vpc.default.id
  subnet_ids      = data.aws_subnets.default.ids
  service_port    = local.service_port
  certificate_arn = aws_acm_certificate_validation.regional.certificate_arn
}

# --- Runtime permissions ---------------------------------------------------

data "aws_iam_policy_document" "task" {
  for_each = local.services

  # every service publishes to its own topic
  dynamic "statement" {
    for_each = contains(local.topology.topics, each.key) ? [1] : []
    content {
      sid       = "PublishOwnEvents"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [module.events.topic_arns[each.key]]
    }
  }

  # and the consumers read their own queue
  dynamic "statement" {
    for_each = contains(keys(local.topology.queues), each.key) ? [1] : []
    content {
      sid    = "ConsumeOwnQueue"
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
      ]
      resources = [module.events.queue_arns[each.key]]
    }
  }

  dynamic "statement" {
    for_each = each.key == "platform" ? [1] : []
    content {
      sid       = "SendVerificationEmail"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [module.email_verification_queue.arn]
    }
  }

  dynamic "statement" {
    for_each = each.key == "platform" ? [1] : []
    content {
      sid       = "Images"
      effect    = "Allow"
      actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      resources = ["${aws_s3_bucket.images.arn}/*"]
    }
  }
}

# --- Services ---------------------------------------------------------------

module "service" {
  source   = "./modules/ecs_app"
  for_each = local.services

  name               = each.key
  cluster_arn        = module.cluster.cluster_arn
  namespace_arn      = module.cluster.namespace_arn
  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [module.cluster.tasks_security_group_id]
  container_port     = local.service_port
  cpu                = each.value.cpu
  memory             = each.value.memory
  ecr_repository_url = module.pbl_api_ecr.url
  image_tag          = "${each.key}-${var.bootstrap_image_tag}"

  health_check_command = "wget -q -O /dev/null http://127.0.0.1:${local.service_port}/health || exit 1"

  environment = merge(
    local.common_environment,
    each.key == "platform" ? local.platform_environment : { AUTH_JWKS_URL = local.jwks_url },
    lookup(local.service_environment, each.key, {}),
    local.database_schema[each.key] == null ? {} : { DATABASE_SCHEMA = local.database_schema[each.key] },
    {
      DATABASE_USERNAME = local.database_user[each.key]
      EVENTS_TOPIC_ARN  = module.events.topic_arns[each.key]
    },
  )
  secrets = local.service_secrets[each.key]

  task_role_policy_json = data.aws_iam_policy_document.task[each.key].json
}

module "gateway" {
  source = "./modules/ecs_app"

  name                = "gateway"
  cluster_arn         = module.cluster.cluster_arn
  namespace_arn       = module.cluster.namespace_arn
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [module.cluster.tasks_security_group_id]
  container_port      = 8080
  cpu                 = 256
  memory              = 512
  ecr_repository_url  = module.gateway_ecr.url
  image_tag           = var.bootstrap_image_tag
  target_group_arn    = module.cluster.gateway_target_group_arn
  expose_in_namespace = false
  attach_task_policy  = false
}

# --- Event bus ---------------------------------------------------------------

module "events" {
  source = "./modules/events"

  topology    = local.topology
  alert_email = var.alert_email
}

data "aws_iam_policy_document" "pbl_api_task" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.email_verification_queue.arn]
  }
}

module "pbl_api" {
  source = "./modules/ecs_service"

  name               = "pbl-api"
  vpc_id             = data.aws_vpc.default.id
  subnet_ids         = data.aws_subnets.default.ids
  container_port     = 3000
  health_check_path  = "/api/health"
  cpu                = 256
  memory             = 512
  desired_count      = 1
  ecr_repository_url = module.pbl_api_ecr.url
  image_tag          = var.pbl_api_bootstrap_image_tag

  task_role_policy_json = data.aws_iam_policy_document.pbl_api_task.json

  environment = {
    NODE_ENV                            = "production"
    APP_NAME                            = "pbl-api"
    APP_DEBUG                           = "false"
    API_PREFIX                          = "api"
    APP_FALLBACK_LANGUAGE               = "en"
    APP_LOG_LEVEL                       = "warn"
    APP_LOG_SERVICE                     = "console"
    APP_CORS_ORIGIN                     = "false"
    DATABASE_TYPE                       = "postgres"
    DATABASE_HOST                       = var.database_host
    DATABASE_USERNAME                   = var.database_username
    DATABASE_NAME                       = var.database_name
    DATABASE_PORT                       = "5432"
    DATABASE_LOGGING                    = "false"
    DATABASE_SYNCHRONIZE                = "false"
    DATABASE_MAX_CONNECTIONS            = "10"
    DATABASE_SSL_ENABLED                = "true"
    DATABASE_REJECT_UNAUTHORIZED        = "true"
    REDIS_HOST                          = var.redis_host
    REDIS_PORT                          = tostring(var.redis_port)
    REDIS_TLS_ENABLED                   = "true"
    SQS_QUEUE_URL                       = module.email_verification_queue.url
    AWS_REGION                          = var.aws_region
    AUTH_JWT_TOKEN_EXPIRES_IN           = "1d"
    AUTH_REFRESH_TOKEN_EXPIRES_IN       = "365d"
    AUTH_FORGOT_TOKEN_EXPIRES_IN        = "7d"
    AUTH_CONFIRM_EMAIL_TOKEN_EXPIRES_IN = "1d"
  }

  secrets = {
    DATABASE_PASSWORD         = aws_ssm_parameter.pbl_api["DATABASE_PASSWORD"].arn
    REDIS_PASSWORD            = aws_ssm_parameter.pbl_api["REDIS_PASSWORD"].arn
    AUTH_JWT_SECRET           = aws_ssm_parameter.pbl_api["AUTH_JWT_SECRET"].arn
    AUTH_REFRESH_SECRET       = aws_ssm_parameter.pbl_api["AUTH_REFRESH_SECRET"].arn
    AUTH_FORGOT_SECRET        = aws_ssm_parameter.pbl_api["AUTH_FORGOT_SECRET"].arn
    AUTH_CONFIRM_EMAIL_SECRET = aws_ssm_parameter.pbl_api["AUTH_CONFIRM_EMAIL_SECRET"].arn
    OBSERVE_APP_KEY           = aws_ssm_parameter.pbl_api["OBSERVE_APP_KEY"].arn
    OBSERVE_APP_SECRET        = aws_ssm_parameter.pbl_api["OBSERVE_APP_SECRET"].arn
  }
}

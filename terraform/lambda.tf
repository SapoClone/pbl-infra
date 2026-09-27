module "pbl_mail_service" {
  source = "./modules/lambda_sqs_consumer"

  name               = "pbl-mail-service"
  ecr_repository_url = module.pbl_mail_service_ecr.url
  image_tag          = var.pbl_mail_service_bootstrap_image_tag
  timeout            = 30
  memory_size        = 512
  batch_size         = 5
  queue_arn          = module.email_verification_queue.arn

  environment = {
    NODE_ENV        = "production"
    APP_NAME        = "pbl-mail-service"
    APP_DEBUG       = "false"
    APP_LOG_LEVEL   = "warn"
    APP_LOG_SERVICE = "console"
    # pbl-api and pbl-mail-service are both provisioned in this same root
    # module, so this can point straight at pbl-api's HTTPS domain instead
    # of a placeholder that needs manual fixing after the fact.
    API_PUBLIC_URL     = "https://api.${var.domain_name}"
    RESEND_API_KEY     = var.resend_api_key
    RESEND_FROM_EMAIL  = var.resend_from_email
    RESEND_FROM_NAME   = var.resend_from_name
    OBSERVE_APP_KEY    = var.observe_app_key
    OBSERVE_APP_SECRET = var.observe_app_secret
  }
}

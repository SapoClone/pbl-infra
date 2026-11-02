# SecureString SSM parameters, referenced by the task definitions' "secrets" block (resolved at container start,
# never baked into the task definition or logged). Values come from secrets.tfvars (gitignored).
#
# Layout:  /pbl/shared/<NAME>               every service (Redis password, service-to-service token)
#          /pbl/<service>/DATABASE_PASSWORD  one Postgres role per service
#          /pbl/platform/<NAME>              token-signing key and platform-only secrets
#          /pbl/integration/<NAME>           marketplace credential encryption key
#
# pbl-mail-service's secrets are plain Lambda environment values in lambda.tf.

locals {
  shared_secrets = {
    REDIS_PASSWORD     = var.redis_password
    INTERNAL_S2S_TOKEN = var.internal_s2s_token
  }

  platform_secrets = {
    AUTH_JWT_PRIVATE_KEY      = var.auth_jwt_private_key
    AUTH_FORGOT_SECRET        = var.auth_forgot_secret
    AUTH_CONFIRM_EMAIL_SECRET = var.auth_confirm_email_secret
    OBSERVE_APP_KEY           = var.observe_app_key
    OBSERVE_APP_SECRET        = var.observe_app_secret
    APP_SWAGGER_USER          = var.swagger_user
    APP_SWAGGER_PASSWORD      = var.swagger_password
  }
}

resource "aws_ssm_parameter" "shared" {
  for_each = nonsensitive(toset(keys(local.shared_secrets)))

  name  = "/pbl/shared/${each.key}"
  type  = "SecureString"
  value = local.shared_secrets[each.key]
}

resource "aws_ssm_parameter" "platform" {
  for_each = nonsensitive(toset(keys(local.platform_secrets)))

  name  = "/pbl/platform/${each.key}"
  type  = "SecureString"
  value = local.platform_secrets[each.key]
}

resource "aws_ssm_parameter" "database" {
  for_each = local.services

  name  = "/pbl/${each.key}/DATABASE_PASSWORD"
  type  = "SecureString"
  value = var.database_passwords[each.key]
}

resource "aws_ssm_parameter" "integration_master_key" {
  name  = "/pbl/integration/INTEGRATION_CREDENTIAL_MASTER_KEY"
  type  = "SecureString"
  value = var.integration_credential_master_key
}

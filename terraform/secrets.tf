# SecureString SSM parameters — referenced by the ECS task definition's
# "secrets" block (resolved at container start, never baked into the task
# definition JSON or logged). This is the "documented in pbl-infra" home
# for every secret pbl-api needs; Terraform is the source of truth for
# which secrets exist, values come from *.tfvars / TF_VAR_* (never
# committed — see .gitignore).
#
# pbl-mail-service's secrets aren't here: Lambda has no equivalent
# SSM-backed "secrets" block on its environment — those go in directly as
# plain (still TF_VAR_-sourced, still gitignored) environment values in
# lambda.tf instead.

locals {
  pbl_api_secrets = {
    DATABASE_PASSWORD         = var.database_password
    REDIS_PASSWORD            = var.redis_password
    AUTH_JWT_SECRET           = var.auth_jwt_secret
    AUTH_REFRESH_SECRET       = var.auth_refresh_secret
    AUTH_FORGOT_SECRET        = var.auth_forgot_secret
    AUTH_CONFIRM_EMAIL_SECRET = var.auth_confirm_email_secret
    OBSERVE_APP_KEY           = var.observe_app_key
    OBSERVE_APP_SECRET        = var.observe_app_secret
    APP_SWAGGER_USER          = var.swagger_user
    APP_SWAGGER_PASSWORD      = var.swagger_password
  }
}

resource "aws_ssm_parameter" "pbl_api" {
  for_each = local.pbl_api_secrets

  name  = "/pbl-api/${each.key}"
  type  = "SecureString"
  value = each.value
}

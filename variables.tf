variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for all resources."
  type        = string
  default     = "asia-southeast1"
}

variable "api_github_owner" {
  description = "GitHub org/user that owns the pbl-api repo."
  type        = string
}

variable "api_github_repo" {
  description = "pbl-api's GitHub repo name."
  type        = string
  default     = "pbl-api"
}

variable "mail_github_owner" {
  description = "GitHub org/user that owns the pbl-mail-service repo."
  type        = string
}

variable "mail_github_repo" {
  description = "pbl-mail-service's GitHub repo name."
  type        = string
  default     = "pbl-mail-service"
}

variable "artifact_repo_id" {
  description = "Artifact Registry repository id (Docker format)."
  type        = string
  default     = "pbl-api"
}

variable "api_service_name" {
  type    = string
  default = "pbl-api"
}

variable "mail_service_name" {
  type    = string
  default = "pbl-mail-service"
}

variable "api_image_tag" {
  type    = string
  default = "latest"
}

variable "mail_image_tag" {
  type    = string
  default = "latest"
}

variable "non_secret_env" {
  description = "Plain (non-secret) env vars for pbl-api."
  type        = map(string)
  default = {
    APP_NAME                            = "pbl-api"
    APP_DEBUG                           = "false"
    API_PREFIX                          = "api"
    APP_FALLBACK_LANGUAGE               = "en"
    APP_LOG_LEVEL                       = "warn"
    APP_LOG_SERVICE                     = "console"
    APP_CORS_ORIGIN                     = "false"
    DATABASE_TYPE                       = "postgres"
    DATABASE_HOST                       = "CHANGE_ME.neon.tech"
    DATABASE_PORT                       = "5432"
    DATABASE_USERNAME                   = "CHANGE_ME"
    DATABASE_NAME                       = "CHANGE_ME"
    DATABASE_LOGGING                    = "false"
    DATABASE_SYNCHRONIZE                = "false"
    DATABASE_MAX_CONNECTIONS            = "10"
    DATABASE_SSL_ENABLED                = "true"
    DATABASE_REJECT_UNAUTHORIZED        = "true"
    REDIS_HOST                          = "CHANGE_ME.upstash.io"
    REDIS_PORT                          = "6379"
    REDIS_TLS_ENABLED                   = "true"
    AUTH_JWT_TOKEN_EXPIRES_IN           = "1d"
    AUTH_REFRESH_TOKEN_EXPIRES_IN       = "365d"
    AUTH_FORGOT_TOKEN_EXPIRES_IN        = "7d"
    AUTH_CONFIRM_EMAIL_TOKEN_EXPIRES_IN = "1d"
  }
}

variable "mail_non_secret_env" {
  description = "Plain (non-secret) env vars for pbl-mail-service."
  type        = map(string)
  default = {
    APP_NAME          = "pbl-mail-service"
    APP_LOG_LEVEL     = "warn"
    APP_LOG_SERVICE   = "console"
    RESEND_FROM_EMAIL = "noreply@example.com"
    RESEND_FROM_NAME  = "pbl-api"
    # Must be set to pbl-api's real public URL (terraform output api_url)
    # after the first apply — see README step 7. Can't be wired
    # automatically as a resource reference: it would create a dependency
    # cycle with api_env's CLOUD_TASKS_MAIL_SERVICE_URL (cloud_run.tf).
    API_PUBLIC_URL = "CHANGE_ME"
  }
}

variable "secret_env_names" {
  description = "pbl-api secret env vars backed by Secret Manager."
  type        = list(string)
  default = [
    "DATABASE_PASSWORD",
    "REDIS_PASSWORD",
    "OBSERVE_APP_KEY",
    "OBSERVE_APP_SECRET",
    "AUTH_JWT_SECRET",
    "AUTH_REFRESH_SECRET",
    "AUTH_FORGOT_SECRET",
    "AUTH_CONFIRM_EMAIL_SECRET",
  ]
}

variable "mail_secret_env_names" {
  description = "pbl-mail-service secret env vars backed by Secret Manager."
  type        = list(string)
  default     = ["RESEND_API_KEY", "OBSERVE_APP_KEY", "OBSERVE_APP_SECRET"]
}

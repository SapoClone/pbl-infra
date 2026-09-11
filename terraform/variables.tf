variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "github_owner" {
  description = "GitHub username/org that owns the pbl-api and pbl-mail-service repos."
  type        = string
}

variable "pbl_api_github_repo" {
  description = "Repo name (not full path) for pbl-api."
  type        = string
  default     = "pbl-api"
}

variable "pbl_mail_service_github_repo" {
  description = "Repo name (not full path) for pbl-mail-service."
  type        = string
  default     = "pbl-mail-service"
}

# --- Shared / observe.nestjs.com ------------------------------------------

variable "observe_app_key" {
  type      = string
  sensitive = true
}

variable "observe_app_secret" {
  type      = string
  sensitive = true
}

# --- pbl-api: database (Neon) ----------------------------------------------

variable "database_host" {
  type = string
}

variable "database_username" {
  type = string
}

variable "database_password" {
  type      = string
  sensitive = true
}

variable "database_name" {
  type = string
}

# --- pbl-api: cache (Upstash Redis) -----------------------------------------

variable "redis_host" {
  type = string
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "redis_password" {
  type      = string
  sensitive = true
}

# --- pbl-api: auth secrets ---------------------------------------------

variable "auth_jwt_secret" {
  type      = string
  sensitive = true
}

variable "auth_refresh_secret" {
  type      = string
  sensitive = true
}

variable "auth_forgot_secret" {
  type      = string
  sensitive = true
}

variable "auth_confirm_email_secret" {
  type      = string
  sensitive = true
}

# --- pbl-mail-service: Resend ------------------------------------------

variable "resend_api_key" {
  type      = string
  sensitive = true
}

variable "resend_from_email" {
  type    = string
  default = "onboarding@resend.dev"
}

variable "resend_from_name" {
  type    = string
  default = "pbl-api"
}

# --- Bootstrap image tags -------------------------------------------------
# The very first `terraform apply` creates the ECS task definition and the
# Lambda function, both of which require an image to already exist at the
# given tag in ECR (AWS validates this at create time — see README "First
# apply" section). Push a real image with these tags before running apply,
# or apply will fail with "image not found".

variable "pbl_api_bootstrap_image_tag" {
  type    = string
  default = "bootstrap"
}

variable "pbl_mail_service_bootstrap_image_tag" {
  type    = string
  default = "bootstrap"
}

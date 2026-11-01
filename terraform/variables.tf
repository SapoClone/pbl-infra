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

# --- Backend: database (Neon) ------------------------------------------------
# One database, one schema and one Postgres role per service (scripts/neon-bootstrap.sql creates them; the role
# of service X is `pbl_X`). Platform runs on `public`, the others on a schema named after the service.

variable "database_host" {
  type = string
}

variable "database_name" {
  type = string
}

variable "database_passwords" {
  description = "Password of each service's Postgres role, by service name (the same values given to scripts/neon-bootstrap.sql)."
  type        = map(string)
  sensitive   = true

  validation {
    condition = toset(keys(var.database_passwords)) == toset([
      "platform", "catalog", "customer", "inventory", "sales", "finance", "integration", "insight",
    ])
    error_message = "database_passwords needs exactly these keys: platform, catalog, customer, inventory, sales, finance, integration, insight."
  }
}

# --- Backend: cache (Upstash Redis) -----------------------------------------

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

# --- Backend: secrets ---------------------------------------------

variable "auth_jwt_private_key" {
  description = "Base64 of a PEM RSA private key (2048-bit) that signs pbl-api access tokens (RS256). Generate: openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 | base64 -w0"
  type        = string
  sensitive   = true
}

variable "internal_s2s_token" {
  description = "Shared secret of service-to-service calls (header x-internal-token, env INTERNAL_S2S_TOKEN). Generate: openssl rand -hex 32. Services fail closed without it."
  type        = string
  sensitive   = true
}

variable "integration_credential_master_key" {
  description = "Key that encrypts marketplace credentials at rest in the integration service. Generate: openssl rand -base64 32"
  type        = string
  sensitive   = true
}

variable "auth_forgot_secret" {
  type      = string
  sensitive = true
}

variable "auth_confirm_email_secret" {
  type      = string
  sensitive = true
}

# --- Platform: Swagger (/api-docs) ---------------------------------------
# Exposes Swagger outside development, behind HTTP Basic Auth, so frontend
# devs have a live reference without needing to run pbl-api locally.

variable "swagger_user" {
  type      = string
  sensitive = true
}

variable "swagger_password" {
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

variable "bootstrap_image_tag" {
  description = "Tag the task definitions point at until the first deploy replaces it (services use <service>-<tag>, the gateway <tag>)."
  type        = string
  default     = "bootstrap"
}

variable "alert_email" {
  description = "Email that receives the dead-letter alarms of the event bus. Empty: alarms exist but notify nobody."
  type        = string
  default     = ""
}

variable "pbl_mail_service_bootstrap_image_tag" {
  type    = string
  default = "bootstrap"
}

# --- Domain --------------------------------------------------------------
# The root domain (makeasy.id.vn) stays managed at iNet — its DNS panel
# has no NS record type, so no Route53 zone hosts any part of this
# domain. Every hostname under it (api.*, static.*, ACM validation
# records) is a plain CNAME added by hand at iNet — see the *_cname
# outputs in outputs.tf for exactly what to paste in.

variable "domain_name" {
  type    = string
  default = "sapo.makeasy.id.vn"
}

variable "root_domain" {
  description = "The zone iNet actually hosts. Used to compute each *_cname output's \"Host\" field relative to it (e.g. \"api.sapo\" instead of the full \"api.sapo.makeasy.id.vn\"), since that's the form iNet's Add Record form expects."
  type        = string
  default     = "makeasy.id.vn"
}

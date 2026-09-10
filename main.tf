locals {
  apis = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudtasks.googleapis.com",
  ]

  all_secret_names = distinct(concat(var.secret_env_names, var.mail_secret_env_names))
}

locals {
  api_accessor_secret_ids  = [for k, v in google_secret_manager_secret.app_secrets : v.id if contains(var.secret_env_names, k)]
  mail_accessor_secret_ids = [for k, v in google_secret_manager_secret.app_secrets : v.id if contains(var.mail_secret_env_names, k)]
}

resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "images" {
  repository_id = var.artifact_repo_id
  location      = var.region
  format        = "DOCKER"
  description   = "pbl-api / pbl-mail-service container images"

  depends_on = [google_project_service.apis]
}

module "api_run_sa" {
  source = "./modules/runtime_service_account"

  account_id   = "pbl-api-run"
  display_name = "pbl-api Cloud Run runtime"
  secret_ids   = local.api_accessor_secret_ids

  depends_on = [google_project_service.apis]
}

module "mail_run_sa" {
  source = "./modules/runtime_service_account"

  account_id   = "pbl-mail-run"
  display_name = "pbl-mail-service Cloud Run runtime"
  secret_ids   = local.mail_accessor_secret_ids

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "app_secrets" {
  for_each = toset(local.all_secret_names)

  secret_id = each.value
  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

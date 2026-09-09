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

resource "google_service_account" "api_run_sa" {
  account_id   = "pbl-api-run"
  display_name = "pbl-api Cloud Run runtime"

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "mail_run_sa" {
  account_id   = "pbl-mail-run"
  display_name = "pbl-mail-service Cloud Run runtime"

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

resource "google_secret_manager_secret_iam_member" "api_sa_accessor" {
  for_each = { for k, v in google_secret_manager_secret.app_secrets : k => v if contains(var.secret_env_names, k) }

  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api_run_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "mail_sa_accessor" {
  for_each = { for k, v in google_secret_manager_secret.app_secrets : k => v if contains(var.mail_secret_env_names, k) }

  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mail_run_sa.email}"
}

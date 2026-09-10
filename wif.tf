resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == \"${var.api_github_owner}/${var.api_github_repo}\" || assertion.repository == \"${var.mail_github_owner}/${var.mail_github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- pbl-api deployer -------------------------------------------------

resource "google_service_account" "api_deployer" {
  account_id   = "pbl-api-deployer"
  display_name = "pbl-api GitHub Actions deployer"

  depends_on = [google_project_service.apis]
}

resource "google_service_account_iam_member" "api_wif_binding" {
  service_account_id = google_service_account.api_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.api_github_owner}/${var.api_github_repo}"
}

resource "google_project_iam_member" "api_deployer_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.api_deployer.email}"
}

resource "google_cloud_run_v2_service_iam_member" "api_deployer_run_admin" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.admin"
  member   = "serviceAccount:${google_service_account.api_deployer.email}"
}

resource "google_service_account_iam_member" "api_deployer_can_act_as_runtime_sa" {
  service_account_id = google_service_account.api_run_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.api_deployer.email}"
}

# --- pbl-mail-service deployer ------------------------------------------

resource "google_service_account" "mail_deployer" {
  account_id   = "pbl-mail-deployer"
  display_name = "pbl-mail-service GitHub Actions deployer"

  depends_on = [google_project_service.apis]
}

resource "google_service_account_iam_member" "mail_wif_binding" {
  service_account_id = google_service_account.mail_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.mail_github_owner}/${var.mail_github_repo}"
}

resource "google_project_iam_member" "mail_deployer_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.mail_deployer.email}"
}

resource "google_cloud_run_v2_service_iam_member" "mail_deployer_run_admin" {
  name     = google_cloud_run_v2_service.mail.name
  location = google_cloud_run_v2_service.mail.location
  role     = "roles/run.admin"
  member   = "serviceAccount:${google_service_account.mail_deployer.email}"
}

resource "google_service_account_iam_member" "mail_deployer_can_act_as_runtime_sa" {
  service_account_id = google_service_account.mail_run_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.mail_deployer.email}"
}

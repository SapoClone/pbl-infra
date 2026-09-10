resource "google_service_account" "this" {
  account_id   = var.account_id
  display_name = var.display_name
}

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.workload_identity_pool_name}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

resource "google_project_iam_member" "artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_cloud_run_v2_service_iam_member" "run_admin" {
  name     = var.cloud_run_service_name
  location = var.cloud_run_service_location
  role     = "roles/run.admin"
  member   = "serviceAccount:${google_service_account.this.email}"
}

resource "google_service_account_iam_member" "can_act_as_runtime_sa" {
  service_account_id = var.runtime_sa_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.this.email}"
}

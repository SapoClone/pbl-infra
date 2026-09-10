output "api_url" {
  description = "Public URL of the API service."
  value       = google_cloud_run_v2_service.api.uri
}

output "artifact_registry_repo" {
  description = "Full path to push Docker images to."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}"
}

output "api_deployer_service_account_email" {
  description = "Service account GitHub Actions impersonates via WIF to deploy pbl-api."
  value       = google_service_account.api_deployer.email
}

output "mail_deployer_service_account_email" {
  description = "Service account GitHub Actions impersonates via WIF to deploy pbl-mail-service."
  value       = google_service_account.mail_deployer.email
}

output "workload_identity_provider" {
  description = "Full resource name to put in the GitHub Actions workflow's `workload_identity_provider` input."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "secret_names" {
  description = "Secret Manager secrets you still need to fill in with real values."
  value       = [for s in google_secret_manager_secret.app_secrets : s.secret_id]
}

output "api_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "mail_service_url" {
  description = "Cloud Tasks target base URL — pbl-api needs this as CLOUD_TASKS_MAIL_SERVICE_URL."
  value       = google_cloud_run_v2_service.mail.uri
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}"
}

output "cloud_tasks_queue_name" {
  description = "Full queue resource name — pbl-api needs this as CLOUD_TASKS_QUEUE_NAME."
  value       = google_cloud_tasks_queue.email.name
}

output "tasks_invoker_service_account_email" {
  description = "pbl-api needs this as CLOUD_TASKS_INVOKER_SA_EMAIL — the OIDC identity it tells Cloud Tasks to present when calling pbl-mail-service."
  value       = google_service_account.tasks_invoker.email
}

output "api_deployer_service_account_email" {
  value = google_service_account.api_deployer.email
}

output "mail_deployer_service_account_email" {
  value = google_service_account.mail_deployer.email
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "secret_names" {
  value = [for s in google_secret_manager_secret.app_secrets : s.secret_id]
}

resource "google_cloud_tasks_queue" "email" {
  name     = "email-verification"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 5
    max_concurrent_dispatches = 5
  }

  retry_config {
    max_attempts  = 5
    min_backoff   = "10s"
    max_backoff   = "300s"
    max_doublings = 4
  }

  depends_on = [google_project_service.apis]
}

# Identity Cloud Tasks presents (as an OIDC token) when it calls
# pbl-mail-service. This is what Cloud Run's IAM checks — NOT pbl-api's
# own runtime SA — since the actual HTTP call is made by the Cloud Tasks
# service on pbl-api's behalf, not by pbl-api's process directly.
resource "google_service_account" "tasks_invoker" {
  account_id   = "pbl-tasks-invoker"
  display_name = "Cloud Tasks -> pbl-mail-service invoker"

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "mail_invocable_by_tasks" {
  name     = module.mail_service.name
  location = module.mail_service.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.tasks_invoker.email}"
}

# pbl-api's runtime SA needs to be allowed to (a) add tasks to the queue,
# and (b) specify tasks_invoker as the OIDC identity on each task it creates.
resource "google_cloud_tasks_queue_iam_member" "api_can_enqueue" {
  name     = google_cloud_tasks_queue.email.name
  location = google_cloud_tasks_queue.email.location
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${module.api_run_sa.email}"
}

resource "google_service_account_iam_member" "api_can_act_as_tasks_invoker" {
  service_account_id = google_service_account.tasks_invoker.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.api_run_sa.email}"
}

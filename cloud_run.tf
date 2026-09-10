locals {
  api_image  = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}/pbl-api:${var.api_image_tag}"
  mail_image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}/pbl-mail-service:${var.mail_image_tag}"

  api_secret_env  = { for k, v in google_secret_manager_secret.app_secrets : k => v.secret_id if contains(var.secret_env_names, k) }
  mail_secret_env = { for k, v in google_secret_manager_secret.app_secrets : k => v.secret_id if contains(var.mail_secret_env_names, k) }

  api_env = merge(var.non_secret_env, {
    NODE_ENV = "production"
    # pbl-api's Cloud Tasks config (cloud-tasks.config.ts) requires all five
    # of these at boot. Wired here as real cross-references (rather than
    # CHANGE_ME placeholders in variables.tf) since this locals block is
    # evaluated after the referenced resources exist.
    GCP_PROJECT_ID       = var.project_id
    CLOUD_TASKS_LOCATION = var.region
    # Bare queue id, NOT the full projects/.../queues/... resource path —
    # CloudTasksService.queuePath() builds the full path itself. The
    # google_cloud_tasks_queue.name attribute is not normalized by the
    # provider, so this stays the short id we set in cloud_tasks.tf.
    CLOUD_TASKS_QUEUE_NAME       = google_cloud_tasks_queue.email.name
    CLOUD_TASKS_MAIL_SERVICE_URL = module.mail_service.uri
    CLOUD_TASKS_INVOKER_SA_EMAIL = google_service_account.tasks_invoker.email
  })

  mail_env = merge(var.mail_non_secret_env, {
    NODE_ENV = "production"
    # API_PUBLIC_URL can't be wired as a real module.api_service.uri
    # reference here: api_env above already depends on module.mail_service,
    # so doing so would create a dependency cycle between the two services.
    # Left as the placeholder in variables.tf's mail_non_secret_env —
    # set it manually after the first apply (see README).
  })
}

# Public HTTP API — scale-to-zero, reachable by anyone.
module "api_service" {
  source = "./modules/cloud_run_service"

  name                  = var.api_service_name
  location              = var.region
  service_account_email = module.api_run_sa.email
  image                 = local.api_image
  env                   = local.api_env
  secret_env            = local.api_secret_env
  allow_public          = true

  depends_on = [google_project_service.apis]
}

# Email sender — scale-to-zero, NOT publicly invokable. Only the Cloud
# Tasks dispatch SA gets roles/run.invoker on it (cloud_tasks.tf).
module "mail_service" {
  source = "./modules/cloud_run_service"

  name                  = var.mail_service_name
  location              = var.region
  service_account_email = module.mail_run_sa.email
  image                 = local.mail_image
  env                   = local.mail_env
  secret_env            = local.mail_secret_env
  allow_public          = false

  depends_on = [google_project_service.apis]
}

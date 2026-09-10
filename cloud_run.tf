locals {
  api_image  = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}/pbl-api:${var.api_image_tag}"
  mail_image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo_id}/pbl-mail-service:${var.mail_image_tag}"

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
    CLOUD_TASKS_MAIL_SERVICE_URL = google_cloud_run_v2_service.mail.uri
    CLOUD_TASKS_INVOKER_SA_EMAIL = google_service_account.tasks_invoker.email
  })

  mail_env = merge(var.mail_non_secret_env, {
    NODE_ENV = "production"
    # API_PUBLIC_URL can't be wired as a real google_cloud_run_v2_service.api.uri
    # reference here: api_env above already depends on google_cloud_run_v2_service.mail,
    # so doing so would create a dependency cycle between the two services.
    # Left as the CHANGE_ME placeholder in variables.tf's mail_non_secret_env —
    # set it manually after the first apply (see README).
  })
}

resource "google_cloud_run_v2_service" "api" {
  name     = var.api_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.api_run_sa.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = local.api_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      ports {
        container_port = 8080
      }

      dynamic "env" {
        for_each = local.api_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = { for k, v in google_secret_manager_secret.app_secrets : k => v if contains(var.secret_env_names, k) }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service" "mail" {
  name     = var.mail_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.mail_run_sa.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = local.mail_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      ports {
        container_port = 8080
      }

      dynamic "env" {
        for_each = local.mail_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = { for k, v in google_secret_manager_secret.app_secrets : k => v if contains(var.mail_secret_env_names, k) }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Deliberately no google_cloud_run_v2_service_iam_member "mail_public" here —
# only the Cloud Tasks dispatch SA (cloud_tasks.tf, Task 12) gets run.invoker.

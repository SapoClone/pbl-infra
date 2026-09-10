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

module "api_deployer" {
  source = "./modules/ci_deployer"

  account_id                  = "pbl-api-deployer"
  display_name                = "pbl-api GitHub Actions deployer"
  workload_identity_pool_name = google_iam_workload_identity_pool.github.name
  github_owner                = var.api_github_owner
  github_repo                 = var.api_github_repo
  project_id                  = var.project_id
  cloud_run_service_name      = module.api_service.name
  cloud_run_service_location  = module.api_service.location
  runtime_sa_name             = module.api_run_sa.name

  depends_on = [google_project_service.apis]
}

module "mail_deployer" {
  source = "./modules/ci_deployer"

  account_id                  = "pbl-mail-deployer"
  display_name                = "pbl-mail-service GitHub Actions deployer"
  workload_identity_pool_name = google_iam_workload_identity_pool.github.name
  github_owner                = var.mail_github_owner
  github_repo                 = var.mail_github_repo
  project_id                  = var.project_id
  cloud_run_service_name      = module.mail_service.name
  cloud_run_service_location  = module.mail_service.location
  runtime_sa_name             = module.mail_run_sa.name

  depends_on = [google_project_service.apis]
}

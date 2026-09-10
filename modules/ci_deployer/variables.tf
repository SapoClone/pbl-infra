variable "account_id" {
  type = string
}

variable "display_name" {
  type = string
}

variable "workload_identity_pool_name" {
  description = "Full resource name of the shared Workload Identity Pool (google_iam_workload_identity_pool.<x>.name)."
  type        = string
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "project_id" {
  type = string
}

variable "cloud_run_service_name" {
  description = "The Cloud Run service this deployer is allowed to deploy to."
  type        = string
}

variable "cloud_run_service_location" {
  type = string
}

variable "runtime_sa_name" {
  description = "Resource name (not email) of the Cloud Run service's runtime service account — this deployer needs roles/iam.serviceAccountUser on it to deploy new revisions."
  type        = string
}

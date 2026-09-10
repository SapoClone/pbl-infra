variable "account_id" {
  description = "Service account id (the part before @project.iam.gserviceaccount.com)."
  type        = string
}

variable "display_name" {
  type = string
}

variable "secret_ids" {
  description = "Secret Manager secret ids this service account should get roles/secretmanager.secretAccessor on."
  type        = list(string)
  default     = []
}

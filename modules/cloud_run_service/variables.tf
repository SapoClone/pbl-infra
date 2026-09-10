variable "name" {
  description = "Cloud Run service name."
  type        = string
}

variable "location" {
  description = "Region to deploy into."
  type        = string
}

variable "service_account_email" {
  description = "Runtime service account for the container."
  type        = string
}

variable "image" {
  description = "Full container image reference (registry/repo/image:tag)."
  type        = string
}

variable "ingress" {
  description = "Cloud Run ingress setting."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
}

variable "min_instance_count" {
  description = "Minimum instances. 0 = scale to zero."
  type        = number
  default     = 0
}

variable "max_instance_count" {
  type    = number
  default = 3
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "cpu_idle" {
  description = "true = CPU only allocated during request handling (scale-to-zero billing). false = CPU always allocated (needed for background work between requests)."
  type        = bool
  default     = true
}

variable "startup_cpu_boost" {
  type    = bool
  default = true
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "env" {
  description = "Plain (non-secret) env vars."
  type        = map(string)
  default     = {}
}

variable "secret_env" {
  description = "Map of env var name => Secret Manager secret_id. Always reads the latest version."
  type        = map(string)
  default     = {}
}

variable "allow_public" {
  description = "If true, grants roles/run.invoker to allUsers (public unauthenticated access). Leave false for services that should only be reachable by a specific caller (e.g. Cloud Tasks' dispatch SA), and grant that access separately at the call site."
  type        = bool
  default     = false
}

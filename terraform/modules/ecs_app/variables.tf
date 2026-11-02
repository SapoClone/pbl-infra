variable "name" {
  description = "Service name. Also the Service Connect name other tasks call (http://<name>:<container_port>), so it must match the hosts in krakend.json."
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "namespace_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "container_port" {
  type = number
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "ecr_repository_url" {
  type = string
}

variable "image_tag" {
  description = "Bootstrap image tag. CI swaps the image on every deploy (the service ignores later task-definition changes)."
  type        = string
}

variable "environment" {
  description = "Plain (non-secret) container environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Env var name to SSM parameter ARN."
  type        = map(string)
  default     = {}
}

variable "task_role_policy_json" {
  description = "Runtime permissions of the app. Set attach_task_policy = false to give the task none."
  type        = string
  default     = null
}

variable "attach_task_policy" {
  description = "Whether task_role_policy_json is attached. A plain bool because the policy text is unknown until apply and cannot drive `count`."
  type        = bool
  default     = true
}

variable "target_group_arn" {
  description = "Attach the service to this ALB target group (the gateway only)."
  type        = string
  default     = null
}

variable "expose_in_namespace" {
  description = "Publish the service under its name in the Service Connect namespace (every backend service; the gateway only calls out)."
  type        = bool
  default     = true
}

variable "health_check_command" {
  description = "Container health check (CMD-SHELL string); null for none."
  type        = string
  default     = null
}

variable "role_prefix" {
  type    = string
  default = "pbl"
}

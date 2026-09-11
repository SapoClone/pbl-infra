variable "name" {
  description = "Service name — used to name the cluster, ALB, task family, log group, etc."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnets — both the ALB and the Fargate tasks sit here directly (no NAT Gateway to keep cost down; tasks get a public IP for outbound egress)."
  type        = list(string)
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "cpu" {
  description = "Fargate task CPU units (256 = .25 vCPU)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "ecr_repository_url" {
  type = string
}

variable "image_tag" {
  description = "Image tag for the task definition's first create. Ignored on later applies — the deploy workflow registers new task def revisions directly."
  type        = string
  default     = "latest"
}

variable "environment" {
  description = "Plain (non-secret) container environment variables."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Sensitive container environment variables, sourced from SSM Parameter Store — map of env var name to SSM parameter ARN."
  type        = map(string)
  default     = {}
}

variable "task_role_policy_json" {
  description = "IAM policy JSON for the task role (the app's own runtime AWS permissions, e.g. SQS SendMessage)."
  type        = string
}

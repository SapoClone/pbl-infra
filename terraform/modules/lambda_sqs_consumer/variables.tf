variable "name" {
  description = "Lambda function name."
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL holding the function's container image."
  type        = string
}

variable "image_tag" {
  description = "Image tag to deploy on first create. Ignored on later applies — see the image_uri lifecycle.ignore_changes note in main.tf."
  type        = string
  default     = "latest"
}

variable "timeout" {
  description = "Function timeout in seconds. Should be well under the queue's visibility_timeout_seconds."
  type        = number
  default     = 30
}

variable "memory_size" {
  type    = number
  default = 512
}

variable "batch_size" {
  type    = number
  default = 5
}

variable "queue_arn" {
  description = "ARN of the SQS queue that triggers this function."
  type        = string
}

variable "environment" {
  description = "Environment variables for the function."
  type        = map(string)
  default     = {}
}

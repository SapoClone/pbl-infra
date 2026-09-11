variable "name" {
  description = "Queue name."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Should be >= the consumer's max processing time (Lambda timeout) to avoid a message being redelivered mid-processing."
  type        = number
  default     = 60
}

variable "name" {
  description = "Cluster name; also names the ALB and security groups."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "namespace_name" {
  description = "ECS Service Connect namespace. Services call each other as http://<service>:<port> inside it."
  type        = string
  default     = "pbl.internal"
}

variable "gateway_port" {
  description = "Container port of the gateway (KrakenD)."
  type        = number
  default     = 8080
}

variable "gateway_health_check_path" {
  type    = string
  default = "/__health"
}

variable "service_port" {
  description = "Container port every backend service listens on."
  type        = number
  default     = 3000
}

variable "certificate_arn" {
  type = string
}

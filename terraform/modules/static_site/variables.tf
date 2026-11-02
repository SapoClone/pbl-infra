variable "bucket_name" {
  description = "S3 bucket holding the built site."
  type        = string
}

variable "domain_name" {
  description = "Hostname the site is served on (the distribution's alias), e.g. app.sapo.makeasy.id.vn."
  type        = string
}

variable "certificate_arn" {
  description = "Validated us-east-1 ACM certificate covering domain_name (CloudFront only takes us-east-1 certificates)."
  type        = string
}

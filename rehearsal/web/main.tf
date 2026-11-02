# pbl-web's hosting against Floci: the real static_site module with a us-east-1 certificate, wired the way web.tf and
# acm.tf wire it. web.sh copies the modules next to this file before applying.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

locals {
  floci = "http://floci:4566"
}

provider "aws" {
  region                      = "ap-southeast-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
  endpoints {
    cloudfront = local.floci
    iam        = local.floci
    s3         = local.floci
    sts        = local.floci
  }
}

provider "aws" {
  alias                       = "us_east_1"
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    acm = local.floci
  }
}

resource "aws_acm_certificate" "web" {
  provider          = aws.us_east_1
  domain_name       = "app.pbl.test"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "web" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.web.arn
  validation_record_fqdns = [tolist(aws_acm_certificate.web.domain_validation_options)[0].resource_record_name]
}

module "web" {
  source = "./modules/static_site"

  bucket_name     = "pbl-web-000000000000"
  domain_name     = "app.pbl.test"
  certificate_arn = aws_acm_certificate_validation.web.certificate_arn
}

output "bucket" {
  value = module.web.bucket_name
}

output "distribution_id" {
  value = module.web.distribution_id
}

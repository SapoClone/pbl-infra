# Offline plan of the whole stack against a mocked AWS provider: catches wiring errors (unknown for_each keys, bad
# references, validation rules) without credentials.   terraform init -backend=false && terraform test
# Needs a provider file like the one Terragrunt generates (provider "aws" + alias us_east_1); CI writes it first.

mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:ap-southeast-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [{
        domain_name           = "api.sapo.makeasy.id.vn"
        resource_record_name  = "_x.api.sapo.makeasy.id.vn."
        resource_record_type  = "CNAME"
        resource_record_value = "_y.acm-validations.aws."
      }]
    }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-00000000" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-a", "subnet-b"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_acm_certificate" {
    defaults = {
      domain_validation_options = [{
        domain_name           = "static.sapo.makeasy.id.vn"
        resource_record_name  = "_x.static.sapo.makeasy.id.vn."
        resource_record_type  = "CNAME"
        resource_record_value = "_y.acm-validations.aws."
      }]
    }
  }
}

variables {
  github_owner                      = "SapoClone"
  observe_app_key                   = "k"
  observe_app_secret                = "s"
  database_host                     = "ep-x.neon.tech"
  database_name                     = "pbl"
  internal_s2s_token                = "t"
  integration_credential_master_key = "m"
  redis_host                        = "r.upstash.io"
  redis_password                    = "p"
  auth_jwt_private_key              = "key"
  auth_forgot_secret                = "f"
  auth_confirm_email_secret         = "c"
  swagger_user                      = "u"
  swagger_password                  = "p"
  resend_api_key                    = "r"
  database_passwords = {
    platform    = "a"
    catalog     = "a"
    customer    = "a"
    inventory   = "a"
    sales       = "a"
    finance     = "a"
    integration = "a"
    insight     = "a"
  }
}

run "plan_everything" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = length(module.service) == 8
    error_message = "eight backend services"
  }
}

run "bad_database_passwords_are_rejected" {
  command = plan

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  variables {
    database_passwords = { platform = "a" }
  }

  expect_failures = [var.database_passwords]
}

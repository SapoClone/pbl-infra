# Root Terragrunt config — every live/<env>/terragrunt.hcl includes this
# for its backend + provider setup, so both are defined exactly once no
# matter how many environments (currently just prod) end up under live/.

locals {
  aws_region = "ap-southeast-1"
}

# S3 backend, with the bucket and DynamoDB lock table created
# automatically on first run if they don't exist yet — this is the actual
# payoff of Terragrunt here: it sidesteps the classic "you need a bucket
# to hold state, but creating that bucket is itself something you'd want
# state for" bootstrap problem that plain Terraform's S3 backend leaves
# to you to solve by hand.
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "pbl-infra-tfstate-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "pbl-infra-tf-locks"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
}

inputs = {
  aws_region = local.aws_region
}

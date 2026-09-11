terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state by default — fine for a single-operator personal project.
  # If more than one person ever runs `terraform apply` here, switch this
  # to an S3 backend (with a DynamoDB lock table) before that happens, or
  # state conflicts will corrupt each other's runs.
  #
  # backend "s3" {
  #   bucket = "<your-state-bucket>"
  #   key    = "pbl-infra/terraform.tfstate"
  #   region = "ap-southeast-1"
  # }
}

provider "aws" {
  region = var.aws_region
}

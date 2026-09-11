terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No provider/backend block here on purpose — Terragrunt generates both
  # (see the root terragrunt.hcl's `generate "provider"` and
  # `remote_state` blocks) so this module stays runnable the same way
  # under any live/<env> without editing it. Running `terraform` directly
  # against this directory (bypassing Terragrunt) won't work as-is —
  # that's intentional; use `terragrunt` from live/prod/ instead.
}

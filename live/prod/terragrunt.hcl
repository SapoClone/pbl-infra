include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_terragrunt_dir()}/../../terraform"

  # secrets.tfvars is gitignored and lives next to this file — Terragrunt
  # doesn't copy files it doesn't know about into its working directory,
  # so it's passed in explicitly by absolute path rather than relying on
  # Terraform's usual auto-loaded *.auto.tfvars convention.
  extra_arguments "secrets" {
    commands  = get_terraform_commands_that_need_vars()
    arguments = ["-var-file=${get_terragrunt_dir()}/secrets.tfvars"]
  }
}

inputs = {
  github_owner = "your-github-username-or-org" # replace with the real owner
}

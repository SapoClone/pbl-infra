variable "name" {
  description = "Short name for this deployer role, e.g. \"pbl-api\". The role is named \"<name>-deployer\"."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo allowed to assume this role, as \"<owner>/<repo>\"."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider (aws_iam_openid_connect_provider), created once in root."
  type        = string
}

variable "policy_json" {
  description = "IAM policy document (JSON) granting this deployer exactly the permissions its deploy workflow needs."
  type        = string
}

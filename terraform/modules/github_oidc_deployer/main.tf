data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # A job that targets a GitHub environment (deploy.yml sets
    # `environment: production`) gets an environment-scoped sub claim
    # ("repo:<owner>/<repo>:environment:production") INSTEAD of the
    # ref-scoped one ("repo:<owner>/<repo>:ref:refs/heads/main") — GitHub
    # only sends one or the other, never both. StringEquals against a list
    # matches if any value matches, so both shapes are accepted here
    # rather than guessing which one applies.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name}-deployer"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-deployer-permissions"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

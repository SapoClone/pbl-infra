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

    # Deploy workflows only ever run on pushes to main (or a manual
    # workflow_dispatch off main) — GitHub's sub claim is the same
    # "repo:<owner>/<repo>:ref:refs/heads/main" shape for both, so this one
    # condition covers everything deploy.yml actually triggers on. A PR
    # from a fork, or a push to any other branch, gets a different sub and
    # is refused.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
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

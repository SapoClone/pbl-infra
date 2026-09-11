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
    # only sends one or the other, never both.
    #
    # On top of that, GitHub now appends "@<numeric id>" to the owner and
    # repo name in some orgs ("repo:owner@123/repo@456:...", to stop a
    # deleted-and-recreated repo/org from inheriting the old one's trust —
    # a real "repo-jacking" mitigation, not a bug) — confirmed empirically
    # via a debug workflow step that printed the actual token claims,
    # since this isn't consistently on for every org/account yet. StringLike
    # (not StringEquals) with a wildcard after the owner/repo name accepts
    # both the plain and the "@id"-suffixed form, so this keeps working
    # whether or not that rolls out further.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:environment:production",
        "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:ref:refs/heads/main",
        "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:environment:production",
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

# One OIDC provider per AWS account, shared by every repo's deploy
# workflow — GitHub's own thumbprint list, so no long-lived AWS access
# keys ever need to live in either repo's secrets.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list is deliberately omitted: on current provider versions
  # it's optional+computed and AWS fetches GitHub's real TLS chain
  # thumbprint itself at apply time. Hand-typing this value is a known
  # footgun (GitHub has rotated it before, and a wrong 40-hex-char string
  # fails closed rather than loudly) — letting AWS derive it avoids that
  # class of mistake entirely.
}

data "aws_iam_policy_document" "pbl_api_deployer" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [module.pbl_api_ecr.arn]
  }

  statement {
    sid       = "EcsDeploy"
    effect    = "Allow"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"] # these two actions don't support resource-level restriction
  }

  statement {
    sid       = "EcsUpdateService"
    effect    = "Allow"
    actions   = ["ecs:UpdateService"]
    resources = ["arn:aws:ecs:${var.aws_region}:*:service/${module.pbl_api.cluster_name}/${module.pbl_api.service_name}"]
  }

  statement {
    sid       = "PassTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [module.pbl_api.task_role_arn]
  }
}

module "pbl_api_deployer" {
  source = "./modules/github_oidc_deployer"

  name              = "pbl-api"
  github_repo       = "${var.github_owner}/${var.pbl_api_github_repo}"
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  policy_json       = data.aws_iam_policy_document.pbl_api_deployer.json
}

data "aws_iam_policy_document" "pbl_mail_service_deployer" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [module.pbl_mail_service_ecr.arn]
  }

  statement {
    sid    = "LambdaDeploy"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      # Used by `aws lambda wait function-updated` in deploy.yml to poll
      # deployment status — a separate action from GetFunction, easy to
      # miss since both look interchangeable from the CLI's perspective.
      "lambda:GetFunctionConfiguration",
    ]
    resources = [module.pbl_mail_service.function_arn]
  }
}

module "pbl_mail_service_deployer" {
  source = "./modules/github_oidc_deployer"

  name              = "pbl-mail-service"
  github_repo       = "${var.github_owner}/${var.pbl_mail_service_github_repo}"
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  policy_json       = data.aws_iam_policy_document.pbl_mail_service_deployer.json
}

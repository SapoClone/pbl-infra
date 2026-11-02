# pbl-web, the admin single-page app, at https://app.<domain>. pbl-web's deploy workflow builds it, syncs dist/ to the
# bucket and invalidates the distribution (the pbl_web_deployer role in iam_oidc.tf).
module "web" {
  source = "./modules/static_site"

  bucket_name     = "pbl-web-${data.aws_caller_identity.current.account_id}"
  domain_name     = "app.${var.domain_name}"
  certificate_arn = aws_acm_certificate_validation.web.certificate_arn
}

module "email_verification_queue" {
  source = "./modules/sqs_queue"
  name   = "email-verification"

  # Must exceed the Lambda's timeout (30s, see lambda.tf) so a message
  # can't become visible again to another poller while still being
  # processed.
  visibility_timeout_seconds = 60
}

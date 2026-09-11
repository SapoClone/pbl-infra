data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-lambda-execution"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissions the SQS poller (part of the Lambda service, running under
# this role) needs to pull messages and delete them on success/report
# partial failures — separate from anything the function's own code does.
data "aws_iam_policy_document" "sqs_trigger" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.queue_arn]
  }
}

resource "aws_iam_role_policy" "sqs_trigger" {
  name   = "${var.name}-sqs-trigger"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.sqs_trigger.json
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "this" {
  function_name = var.name
  role          = aws_iam_role.execution.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:${var.image_tag}"
  timeout       = var.timeout
  memory_size   = var.memory_size

  environment {
    variables = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_cloudwatch_log_group.this,
  ]

  lifecycle {
    # The deploy workflow updates the running image via `aws lambda
    # update-function-code` directly (see pbl-mail-service's deploy.yml) —
    # letting Terraform track image_uri would fight that on every apply,
    # reverting to whatever tag was last planned instead of the tag CI
    # just deployed.
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = var.queue_arn
  function_name    = aws_lambda_function.this.arn
  batch_size       = var.batch_size

  # Lets the handler report which messages in a batch failed (via
  # SQSBatchResponse.batchItemFailures) so only those are retried, instead
  # of one bad message in a batch forcing the whole batch to be
  # reprocessed. src/lambda.ts already returns this shape.
  function_response_types = ["ReportBatchItemFailures"]
}

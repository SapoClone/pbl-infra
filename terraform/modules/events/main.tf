# The event bus of ADR-0007: one SNS topic per producing service (`pbl-<producer>-events`), one SQS queue per
# consuming service (`<service>-events`) with a DLQ (`<service>-events-dlq`), and a subscription per
# (consumer, producer) pair with raw message delivery and a filter on the `type` message attribute.
# Names must match libs/events/src/queue-names.ts.

locals {
  subscriptions = merge([
    for consumer, producers in var.topology.queues : {
      for producer, types in producers : "${consumer}:${producer}" => {
        consumer = consumer
        producer = producer
        types    = types
      }
    }
  ]...)
}

resource "aws_sns_topic" "producer" {
  for_each = toset(var.topology.topics)
  name     = "pbl-${each.key}-events"
}

resource "aws_sqs_queue" "dlq" {
  for_each                  = var.topology.queues
  name                      = "${each.key}-events-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum: time to notice and redrive
}

resource "aws_sqs_queue" "consumer" {
  for_each                   = var.topology.queues
  name                       = "${each.key}-events"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Only the topics a queue subscribes to may send to it.
data "aws_iam_policy_document" "queue" {
  for_each = var.topology.queues

  statement {
    sid       = "AllowSubscribedTopics"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.consumer[each.key].arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for producer in keys(each.value) : aws_sns_topic.producer[producer].arn]
    }
  }
}

resource "aws_sqs_queue_policy" "consumer" {
  for_each  = var.topology.queues
  queue_url = aws_sqs_queue.consumer[each.key].id
  policy    = data.aws_iam_policy_document.queue[each.key].json
}

resource "aws_sns_topic_subscription" "this" {
  for_each = local.subscriptions

  topic_arn            = aws_sns_topic.producer[each.value.producer].arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.consumer[each.value.consumer].arn
  raw_message_delivery = true # without it the body is wrapped in an SNS envelope and every consumer fails
  filter_policy_scope  = "MessageAttributes"
  filter_policy        = jsonencode({ type = sort(each.value.types) })

  depends_on = [aws_sqs_queue_policy.consumer]
}

# --- Alarms: a message in a DLQ is an event nobody could process ------------

resource "aws_sns_topic" "alerts" {
  name = "pbl-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = var.topology.queues

  alarm_name          = "${each.key}-events-dlq-not-empty"
  alarm_description   = "Dead letters in ${each.key}-events-dlq. Inspect, fix, then: node scripts/redrive-dlq.js ${each.key}"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq[each.key].name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

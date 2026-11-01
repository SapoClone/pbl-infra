# SapoClone v2 Event Bus Topology (Outbox -> SNS topic per producer -> SQS queue + DLQ per consumer)
# Mirrors libs/contracts/src/topology.ts in pbl-api.

locals {
  event_producer_services = toset([
    "platform",
    "catalog",
    "inventory",
    "sales",
    "customer",
    "finance",
    "integration",
  ])

  event_consumer_services = toset([
    "catalog",
    "inventory",
    "sales",
    "customer",
    "finance",
    "integration",
    "insight",
  ])

  # Map of consumer service -> list of producer services whose SNS topic it subscribes to.
  service_topic_subscriptions = {
    catalog     = ["platform"]
    inventory   = ["platform", "catalog"]
    sales       = ["platform", "inventory"]
    customer    = ["platform", "sales"]
    finance     = ["platform", "sales"]
    integration = ["platform", "sales"]
    insight     = ["platform", "catalog", "inventory", "sales", "customer", "finance"]
  }

  # Flattened consumer:producer subscription pairs for aws_sns_topic_subscription.
  sns_sqs_subscription_pairs = var.enable_microservices_topology ? merge([
    for consumer, producers in local.service_topic_subscriptions : {
      for producer in producers : "${consumer}__from__${producer}" => {
        consumer = consumer
        producer = producer
      }
    }
  ]...) : {}
}

resource "aws_sns_topic" "service_events" {
  for_each = var.enable_microservices_topology ? local.event_producer_services : toset([])

  name = "pbl-${each.key}-events"
}

module "service_event_queues" {
  source   = "./modules/sqs_queue"
  for_each = var.enable_microservices_topology ? local.event_consumer_services : toset([])

  name                       = "pbl-${each.key}-events"
  visibility_timeout_seconds = 60
}

resource "aws_sqs_queue_policy" "service_event_queues" {
  for_each = var.enable_microservices_topology ? local.event_consumer_services : toset([])

  queue_url = module.service_event_queues[each.key].url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSubscribedSnsTopicsToSendMessage"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = module.service_event_queues[each.key].arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = [
              for producer in local.service_topic_subscriptions[each.key] :
              aws_sns_topic.service_events[producer].arn
            ]
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "service_event_subscriptions" {
  for_each = local.sns_sqs_subscription_pairs

  topic_arn            = aws_sns_topic.service_events[each.value.producer].arn
  protocol             = "sqs"
  endpoint             = module.service_event_queues[each.value.consumer].arn
  raw_message_delivery = true
}

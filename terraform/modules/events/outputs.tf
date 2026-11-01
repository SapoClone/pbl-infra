output "topic_arns" {
  description = "Producer => topic ARN (EVENTS_TOPIC_ARN of that producer)."
  value       = { for k, t in aws_sns_topic.producer : k => t.arn }
}

output "queue_arns" {
  description = "Consumer => queue ARN."
  value       = { for k, q in aws_sqs_queue.consumer : k => q.arn }
}

output "dlq_arns" {
  value = { for k, q in aws_sqs_queue.dlq : k => q.arn }
}

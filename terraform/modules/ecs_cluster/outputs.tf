output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "namespace_arn" {
  value = aws_service_discovery_http_namespace.this.arn
}

output "tasks_security_group_id" {
  value = aws_security_group.tasks.id
}

output "gateway_target_group_arn" {
  value = aws_lb_target_group.gateway.arn
  # ECS rejects a service whose target group has no listener yet, and the ALB takes minutes to create
  depends_on = [aws_lb_listener.https]
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_listener_arn" {
  value = aws_lb_listener.https.arn
}

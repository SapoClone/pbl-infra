output "pbl_api_url" {
  value = "http://${module.pbl_api.alb_dns_name}"
}

output "pbl_api_ecr_url" {
  value = module.pbl_api_ecr.url
}

output "pbl_mail_service_ecr_url" {
  value = module.pbl_mail_service_ecr.url
}

output "email_verification_queue_url" {
  value = module.email_verification_queue.url
}

output "pbl_api_deployer_role_arn" {
  description = "Set as the AWS_DEPLOYER_ROLE_ARN repo variable in pbl-api."
  value       = module.pbl_api_deployer.role_arn
}

output "pbl_mail_service_deployer_role_arn" {
  description = "Set as the AWS_DEPLOYER_ROLE_ARN repo variable in pbl-mail-service."
  value       = module.pbl_mail_service_deployer.role_arn
}

output "pbl_api_ecs_cluster" {
  value = module.pbl_api.cluster_name
}

output "pbl_api_ecs_service" {
  value = module.pbl_api.service_name
}

output "pbl_api_ecs_task_family" {
  value = module.pbl_api.task_family
}

output "pbl_mail_service_lambda_function_name" {
  value = module.pbl_mail_service.function_name
}

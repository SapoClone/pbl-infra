output "pbl_api_url" {
  value = "http://${module.pbl_api.alb_dns_name}"
}

output "pbl_api_ecr_url" {
  description = "Full repository URL (registry + name) — for reference, not what deploy.yml's AWS_ECR_REPOSITORY variable wants."
  value       = module.pbl_api_ecr.url
}

output "pbl_api_ecr_name" {
  description = "Bare repository name. Set as the AWS_ECR_REPOSITORY repo variable in pbl-api — deploy.yml concatenates this with the registry hostname itself, so the full URL here would duplicate it."
  value       = module.pbl_api_ecr.name
}

output "pbl_mail_service_ecr_url" {
  description = "Full repository URL (registry + name) — for reference, not what deploy.yml's AWS_ECR_REPOSITORY variable wants."
  value       = module.pbl_mail_service_ecr.url
}

output "pbl_mail_service_ecr_name" {
  description = "Bare repository name. Set as the AWS_ECR_REPOSITORY repo variable in pbl-mail-service — same reasoning as pbl_api_ecr_name."
  value       = module.pbl_mail_service_ecr.name
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

output "pbl_api_https_url" {
  value = "https://api.${var.domain_name}"
}

output "image_bucket_name" {
  value = aws_s3_bucket.images.id
}

output "image_cdn_url" {
  value = "https://static.${var.domain_name}"
}

output "acm_regional_validation_cname" {
  description = "Add this as a CNAME record at iNet before the regional ACM cert (api.*) can validate. Print with: terragrunt output -raw acm_regional_validation_cname"
  value       = <<-EOT
    Type:  CNAME
    Host:  ${trimsuffix(tolist(aws_acm_certificate.regional.domain_validation_options)[0].resource_record_name, ".${var.root_domain}.")}
    Value: ${tolist(aws_acm_certificate.regional.domain_validation_options)[0].resource_record_value}
  EOT
}

output "acm_us_east_1_validation_cname" {
  description = "Add this as a CNAME record at iNet before the us-east-1 ACM cert (static.*, for CloudFront) can validate. Print with: terragrunt output -raw acm_us_east_1_validation_cname"
  value       = <<-EOT
    Type:  CNAME
    Host:  ${trimsuffix(tolist(aws_acm_certificate.us_east_1.domain_validation_options)[0].resource_record_name, ".${var.root_domain}.")}
    Value: ${tolist(aws_acm_certificate.us_east_1.domain_validation_options)[0].resource_record_value}
  EOT
}

output "pbl_api_cname" {
  description = "Add this as a CNAME record at iNet to make api.sapo.makeasy.id.vn reach pbl-api's ALB. Print with: terragrunt output -raw pbl_api_cname"
  value       = <<-EOT
    Type:  CNAME
    Host:  ${trimsuffix("api.${var.domain_name}", ".${var.root_domain}")}
    Value: ${module.pbl_api.alb_dns_name}
  EOT
}

output "image_cdn_cname" {
  description = "Add this as a CNAME record at iNet to make static.sapo.makeasy.id.vn reach the image CDN. Print with: terragrunt output -raw image_cdn_cname"
  value       = <<-EOT
    Type:  CNAME
    Host:  ${trimsuffix("static.${var.domain_name}", ".${var.root_domain}")}
    Value: ${aws_cloudfront_distribution.images.domain_name}
  EOT
}

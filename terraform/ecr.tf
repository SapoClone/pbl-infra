module "pbl_api_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-api"
}

module "pbl_mail_service_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-mail-service"
}

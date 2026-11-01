# One repository for every backend service (tags: <service>-<git sha>), one for the gateway, one for the mail Lambda.
module "pbl_api_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-api"
}

module "gateway_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-gateway"
}

module "pbl_mail_service_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-mail-service"
}

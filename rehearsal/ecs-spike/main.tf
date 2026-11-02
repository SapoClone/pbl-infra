# The ECS half of ../../terraform against Floci: the same modules, wired the way services.tf wires them, with the
# echo image in place of the service images. spike.sh copies the modules next to this file before applying.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region                      = "ap-southeast-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    acm              = "http://floci:4566"
    cloudwatch       = "http://floci:4566"
    ec2              = "http://floci:4566"
    ecr              = "http://floci:4566"
    ecs              = "http://floci:4566"
    elbv2            = "http://floci:4566"
    iam              = "http://floci:4566"
    logs             = "http://floci:4566"
    servicediscovery = "http://floci:4566"
    ssm              = "http://floci:4566"
    sts              = "http://floci:4566"
  }
}

locals {
  service_port = 3000
  services     = toset(["inventory", "sales"])
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_acm_certificate" "regional" {
  domain_name       = "api.pbl.test"
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "regional" {
  certificate_arn         = aws_acm_certificate.regional.arn
  validation_record_fqdns = [tolist(aws_acm_certificate.regional.domain_validation_options)[0].resource_record_name]
}

module "pbl_api_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-api"
}

module "gateway_ecr" {
  source = "./modules/ecr_repository"
  name   = "pbl-gateway"
}

module "cluster" {
  source = "./modules/ecs_cluster"

  name            = "pbl"
  vpc_id          = data.aws_vpc.default.id
  subnet_ids      = data.aws_subnets.default.ids
  service_port    = local.service_port
  certificate_arn = aws_acm_certificate_validation.regional.certificate_arn
}

resource "aws_ssm_parameter" "secret" {
  name  = "/pbl/spike/SPIKE_SECRET"
  type  = "SecureString"
  value = "from-ssm"
}

data "aws_iam_policy_document" "task" {
  statement {
    actions   = ["sns:Publish"]
    resources = ["*"]
  }
}

module "service" {
  source   = "./modules/ecs_app"
  for_each = local.services

  name               = each.key
  cluster_arn        = module.cluster.cluster_arn
  namespace_arn      = module.cluster.namespace_arn
  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = [module.cluster.tasks_security_group_id]
  container_port     = local.service_port
  cpu                = 256
  memory             = 512
  ecr_repository_url = module.pbl_api_ecr.url
  image_tag          = "${each.key}-spike"

  health_check_command = "wget -q -O /dev/null http://127.0.0.1:${local.service_port}/health || exit 1"

  environment = { PORT = tostring(local.service_port), SERVICE_NAME = each.key }
  secrets     = { SPIKE_SECRET = aws_ssm_parameter.secret.arn }

  task_role_policy_json = data.aws_iam_policy_document.task.json
}

module "gateway" {
  source = "./modules/ecs_app"

  name                = "gateway"
  cluster_arn         = module.cluster.cluster_arn
  namespace_arn       = module.cluster.namespace_arn
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [module.cluster.tasks_security_group_id]
  container_port      = 8080
  cpu                 = 256
  memory              = 512
  ecr_repository_url  = module.gateway_ecr.url
  image_tag           = "spike"
  target_group_arn    = module.cluster.gateway_target_group_arn
  expose_in_namespace = false
  attach_task_policy  = false

  environment = { PORT = "8080", SERVICE_NAME = "gateway" }
  secrets     = { SPIKE_SECRET = aws_ssm_parameter.secret.arn }
}

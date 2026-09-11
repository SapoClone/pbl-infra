# The account's default VPC + its default (public) subnets — one per AZ,
# already internet-routable. Good enough for this project's scale, and
# avoids the cost/complexity of a NAT Gateway: ECS tasks get a public IP
# directly (see ecs_service module) instead of routing egress through one.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

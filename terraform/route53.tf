# Public hosted zone for the delegated subdomain. The root domain
# (makeasy.id.vn) stays managed at iNet — after this zone is created,
# add one NS record there: "sapo" -> the 4 nameservers in the
# route53_name_servers output. Every record below (and every ACM
# validation record in acm.tf) then resolves automatically, with no
# further manual DNS steps at iNet.
resource "aws_route53_zone" "this" {
  name = var.domain_name
}

resource "aws_route53_record" "pbl_api" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.pbl_api.alb_dns_name
    zone_id                = module.pbl_api.alb_zone_id
    evaluate_target_health = false
  }
}

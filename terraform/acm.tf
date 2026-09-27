# Regional cert (ap-southeast-1) — for the ALB's HTTPS listener.
resource "aws_acm_certificate" "regional" {
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "regional_validation" {
  for_each = {
    for dvo in aws_acm_certificate.regional.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "regional" {
  certificate_arn         = aws_acm_certificate.regional.arn
  validation_record_fqdns = [for r in aws_route53_record.regional_validation : r.fqdn]
}

# us-east-1 cert — required by CloudFront regardless of the stack's home
# region. Covers the CDN's own hostname.
resource "aws_acm_certificate" "us_east_1" {
  provider          = aws.us_east_1
  domain_name       = "static.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "us_east_1_validation" {
  for_each = {
    for dvo in aws_acm_certificate.us_east_1.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "us_east_1" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.us_east_1.arn
  validation_record_fqdns = [for r in aws_route53_record.us_east_1_validation : r.fqdn]
}

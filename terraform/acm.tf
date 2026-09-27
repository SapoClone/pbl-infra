# Regional cert (ap-southeast-1) — for the ALB's HTTPS listener.
resource "aws_acm_certificate" "regional" {
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation for this cert is a CNAME added by hand at iNet (see the
# acm_regional_validation_cname output in outputs.tf) — there's no
# Route53 zone for this domain to create the record in automatically.
# ACM's validation is a plain public DNS lookup, so it doesn't matter who
# hosts the record; this resource just polls until it resolves. Each cert
# only requests one domain name, so domain_validation_options always has
# exactly one element.
resource "aws_acm_certificate_validation" "regional" {
  certificate_arn         = aws_acm_certificate.regional.arn
  validation_record_fqdns = [tolist(aws_acm_certificate.regional.domain_validation_options)[0].resource_record_name]
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

# See the comment on aws_acm_certificate_validation.regional above — same
# reasoning, validated via a manually-added CNAME at iNet (the
# acm_us_east_1_validation_cname output).
resource "aws_acm_certificate_validation" "us_east_1" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.us_east_1.arn
  validation_record_fqdns = [tolist(aws_acm_certificate.us_east_1.domain_validation_options)[0].resource_record_name]
}

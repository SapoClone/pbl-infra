resource "aws_cloudfront_origin_access_control" "images" {
  name                              = "pbl-images-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "images" {
  aliases         = ["static.${var.domain_name}"]
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_200" # includes Asia-Pacific edges

  origin {
    domain_name              = aws_s3_bucket.images.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.images.id
    origin_id                = aws_s3_bucket.images.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = aws_s3_bucket.images.id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.us_east_1.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

data "aws_iam_policy_document" "images_cloudfront_read" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.images.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.images.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id
  policy = data.aws_iam_policy_document.images_cloudfront_read.json
}

resource "aws_route53_record" "images_cdn" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "static.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.images.domain_name
    zone_id                = aws_cloudfront_distribution.images.hosted_zone_id
    evaluate_target_health = false
  }
}

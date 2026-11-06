data "aws_caller_identity" "current" {}

# Private bucket for product/user images. Never public — CloudFront
# (cloudfront.tf) is the only reader, via Origin Access Control.
resource "aws_s3_bucket" "images" {
  bucket = "pbl-images-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Browsers upload straight to the bucket with a presigned PUT that catalog issues (pbl-api docs/guides/uploads.md).
# Reads still go through CloudFront; GET/HEAD here only serve a direct link.
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_origins = ["https://app.${var.domain_name}"]
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_headers = ["Content-Type", "Content-Length", "x-amz-*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Housekeeping the API cannot do: half-finished multipart uploads, and anything under tmp/ (scratch objects).
# Unattached images are deleted by catalog's own cleanup job, so nothing else expires here.
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "expire-tmp"
    status = "Enabled"

    filter {
      prefix = "tmp/"
    }

    expiration {
      days = 1
    }
  }
}

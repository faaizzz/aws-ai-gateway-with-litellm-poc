# Private S3 bucket behind CloudFront (OAC) hosting the Antora docs site.
resource "aws_s3_bucket" "docs" {
  bucket = "ai-gw-docs-site-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public documentation only: SSE-S3 is enough, a customer-managed KMS key
# would add cost and a CloudFront/KMS policy for no benefit.
# trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "docs" {
  name                              = "ai-gw-docs-site"
  description                       = "OAC for the docs bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# HTTP basic auth in front of the whole site. Only the password's SHA-256 is
# embedded; the viewer-request function runs before the cache.
resource "aws_cloudfront_function" "docs_basic_auth" {
  name    = "ai-gw-docs-basic-auth"
  runtime = "cloudfront-js-2.0"
  comment = "Basic auth for the docs site"
  publish = true
  code = replace(
    replace(file("${path.module}/functions/docs-basic-auth.js"), "__USER__", var.docs_basic_auth_user),
    "__PASSWORD_SHA256__", var.docs_basic_auth_password_sha256
  )
}

# AWS-managed policies, looked up by name so no IDs are hard-coded.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

# Static, read-only site with no user input; a WAF web ACL is a fixed monthly
# cost that this demo does not justify.
# trivy:ignore:AWS-0011
resource "aws_cloudfront_distribution" "docs" {
  enabled             = true
  comment             = "Antora documentation site"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.docs.bucket_regional_domain_name
    origin_id                = "docs-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.docs.id
  }

  default_cache_behavior {
    target_origin_id           = "docs-s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.docs_basic_auth.arn
    }
  }

  # A private bucket answers 403 for missing keys.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "docs_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.docs.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.docs.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "docs" {
  bucket = aws_s3_bucket.docs.id
  policy = data.aws_iam_policy_document.docs_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.docs]
}

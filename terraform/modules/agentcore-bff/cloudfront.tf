# Security Headers Policy
resource "aws_cloudfront_response_headers_policy" "security" {
  count = var.enable_bff ? 1 : 0
  name  = "agentcore-bff-security-${var.agent_name}"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
  }
}

resource "aws_cloudfront_distribution" "bff" {
  # checkov:skip=CKV2_AWS_47: WAF requires cost/complexity decision (out of scope for harness)
  # checkov:skip=CKV2_AWS_42: Custom SSL requires ACM cert (out of scope for harness default)
  # checkov:skip=CKV2_AWS_46: S3 Origin Access is enabled via OAC
  count = var.enable_bff ? 1 : 0

  origin {
    domain_name              = aws_s3_bucket.spa[0].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.spa[0].id
    origin_id                = "S3-SPA"
  }

  origin {
    domain_name = "${aws_api_gateway_rest_api.bff[0].id}.execute-api.${var.region}.amazonaws.com"
    origin_id   = "APIGateway"
    origin_path = "/${var.environment}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Default Behavior: S3 (Frontend)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-SPA"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id

    viewer_protocol_policy = "redirect-to-https"

    # Senior Engineer: Prevent index.html caching
    # This ensures new deploys are visible immediately
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # API Behavior
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "APIGateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Cookie", "Origin"] # CORS/Auth
      cookies {
        forward = "all"
      }
    }

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # Auth Behavior
  ordered_cache_behavior {
    path_pattern     = "/auth/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "APIGateway"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Cookie", "Origin"]
      cookies {
        forward = "all"
      }
    }

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # SPA Fallback
  custom_error_response {
    error_code         = 403 # S3 returns 403 for private objects
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  tags = var.tags
}

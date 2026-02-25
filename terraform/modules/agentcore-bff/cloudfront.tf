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

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_function" "spa_route_rewrite" {
  count   = var.enable_bff ? 1 : 0
  name    = "agentcore-bff-spa-rewrite-${var.agent_name}"
  runtime = "cloudfront-js-2.0"
  publish = true
  comment = "Rewrite SPA deep links to index.html without altering /api or /auth responses"

  code = <<-EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri || "/";

      if (
        uri === "/" ||
        uri === "/api" ||
        uri === "/auth" ||
        uri.indexOf("/api/") === 0 ||
        uri.indexOf("/auth/") === 0
      ) {
        return request;
      }

      if (uri.charAt(uri.length - 1) === "/") {
        request.uri = "/index.html";
        return request;
      }

      var lastSlash = uri.lastIndexOf("/");
      var lastSegment = uri.substring(lastSlash + 1);

      if (lastSegment.indexOf(".") === -1) {
        request.uri = "/index.html";
      }

      return request;
    }
  EOF
}

resource "aws_cloudfront_distribution" "bff" {
  # checkov:skip=CKV2_AWS_47: WAF association is optional; configure via cloudfront_waf_acl_arn for enterprise deployments
  # checkov:skip=CKV2_AWS_42: Custom SSL requires ACM cert (out of scope for harness default)
  # checkov:skip=CKV2_AWS_46: S3 Origin Access is enabled via OAC
  # checkov:skip=CKV_AWS_310: Intentional harness default; origin failover needs multi-region BFF/API topology and cutover design (#79)
  # checkov:skip=CKV_AWS_374: Intentional harness default; geo restrictions are workload policy choices and typically enforced in WAF
  count = var.enable_bff ? 1 : 0

  # Optional WAFv2 CLOUDFRONT-scope Web ACL association (must be in us-east-1)
  web_acl_id = var.cloudfront_waf_acl_arn != "" ? var.cloudfront_waf_acl_arn : null

  aliases = var.custom_domain_name != "" ? [var.custom_domain_name] : []

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

  logging_config {
    bucket          = local.cloudfront_access_logs_bucket_domain
    include_cookies = false
    prefix          = "${local.cloudfront_access_logs_prefix}${var.agent_name}/${var.environment}/"
  }

  # Default Behavior: S3 (Frontend)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-SPA"
    cache_policy_id  = data.aws_cloudfront_cache_policy.caching_disabled.id

    # No origin request policy on the SPA behavior: the managed disabled cache policy
    # already preserves the prior "forward nothing" semantics (no cookies/query strings/headers).

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id

    # SPA deep-link fallback is handled on viewer-request so /api and /auth errors
    # preserve their origin status codes instead of being rewritten to index.html.
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_route_rewrite[0].arn
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  # API Behavior
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "APIGateway"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id

    viewer_protocol_policy = "https-only"
  }

  # Auth Behavior
  ordered_cache_behavior {
    path_pattern             = "/auth/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "APIGateway"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id

    response_headers_policy_id = aws_cloudfront_response_headers_policy.security[0].id

    viewer_protocol_policy = "https-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != "" ? "TLSv1.2_2021" : "TLSv1"
  }

  tags = var.tags
}

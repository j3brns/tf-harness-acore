# WAF for API Gateway protection
resource "aws_wafv2_web_acl" "main" {
  # checkov:skip=CKV_AWS_176: Default action is Allow to prevent accidental broad lockout in this harness
  count = var.enable_waf ? 1 : 0
  name  = "agentcore-waf-${var.agent_name}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: IP Rate Limiting (Flood Protection)
  rule {
    name     = "IPRateLimit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules (SQLi, Common Bad Inputs)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "agentcore-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# WAF Logging
resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_waf ? 1 : 0

  # WAF logging requires the log group name to start with aws-waf-logs-
  name              = "aws-waf-logs-agentcore-${var.agent_name}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count = var.enable_waf ? 1 : 0

  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]
  resource_arn            = aws_wafv2_web_acl.main[0].arn
}

output "waf_acl_arn" {
  description = "ARN of the WAFv2 Web ACL, or null if WAF is disabled"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

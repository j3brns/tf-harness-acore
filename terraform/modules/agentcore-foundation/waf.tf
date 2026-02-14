# WAF for API Gateway protection
resource "aws_wafv2_web_acl" "main" {
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

output "waf_acl_arn" {
  value = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

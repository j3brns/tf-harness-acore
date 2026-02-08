# CloudWatch Log Group for Agent Runtime
resource "aws_cloudwatch_log_group" "agentcore" {
  count = var.enable_observability ? 1 : 0

  name              = "/aws/bedrock/agentcore/runtime/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags

  depends_on = [aws_cloudwatch_log_resource_policy.bedrock_agentcore]
}

# X-Ray Sampling Rule for AgentCore
resource "aws_xray_sampling_rule" "agentcore" {
  count = var.enable_observability && var.enable_xray ? 1 : 0

  rule_name      = "${var.agent_name}-sampling"
  priority       = 100
  fixed_rate     = var.xray_sampling_rate
  reservoir_size = 1
  service_type   = "AWS::BedrockAgentCore"
  service_name   = var.agent_name
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  resource_arn   = "*"
  version        = 1

  attributes = {
    "Environment" = var.environment
    "Agent"       = var.agent_name
  }

  tags = var.tags
}

# X-Ray Group for error tracking
resource "aws_xray_group" "agentcore_errors" {
  count = var.enable_observability && var.enable_xray ? 1 : 0

  group_name        = "${var.agent_name}-errors"
  filter_expression = "status code >= 400"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = false
  }

  tags = var.tags
}

# Metric Alarms for gateway health
resource "aws_cloudwatch_metric_alarm" "gateway_errors" {
  count = var.enable_observability && var.enable_gateway ? 1 : 0

  alarm_name          = "${var.agent_name}-gateway-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/BedrockAgentCore"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when gateway errors exceed threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    GatewayId = var.enable_gateway ? data.external.gateway_output[0].result.gatewayId : ""
  }

  tags = var.tags
}

# Metric Alarm for target invocation duration
resource "aws_cloudwatch_metric_alarm" "target_duration" {
  count = var.enable_observability && var.enable_gateway ? 1 : 0

  alarm_name          = "${var.agent_name}-target-duration"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetInvocationDuration"
  namespace           = "AWS/BedrockAgentCore"
  period              = "300"
  statistic           = "Average"
  threshold           = "30000" # 30 seconds in milliseconds
  alarm_description   = "Alert when target invocation duration is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    GatewayId = var.enable_gateway ? data.external.gateway_output[0].result.gatewayId : ""
  }

  tags = var.tags
}

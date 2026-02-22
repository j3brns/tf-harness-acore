# Per-agent CloudWatch dashboard (Issue #10)
locals {
  agent_dashboard_name_effective = trimspace(var.agent_dashboard_name) != "" ? var.agent_dashboard_name : "${var.agent_name}-dashboard"
  dashboard_region_effective     = trimspace(var.dashboard_region) != "" ? var.dashboard_region : var.region
}

locals {
  agent_dashboard_metric_widgets = var.enable_gateway ? [
    {
      type = "metric"
      properties = {
        title  = "Gateway Errors"
        region = local.dashboard_region_effective
        view   = "timeSeries"
        stat   = "Sum"
        period = 300
        metrics = [
          ["AWS/BedrockAgentCore", "Errors", "GatewayId", local.gateway_id]
        ]
      }
    },
    {
      type = "metric"
      properties = {
        title  = "Gateway Target Invocation Duration (Avg ms)"
        region = local.dashboard_region_effective
        view   = "timeSeries"
        stat   = "Average"
        period = 300
        metrics = [
          ["AWS/BedrockAgentCore", "TargetInvocationDuration", "GatewayId", local.gateway_id]
        ]
      }
    }
  ] : []

  agent_dashboard_log_widgets = concat(
    var.enable_gateway ? [
      {
        type = "log"
        properties = {
          title  = "Gateway Logs"
          region = local.dashboard_region_effective
          view   = "table"
          query  = "SOURCE '/aws/bedrock/agentcore/gateway/${var.agent_name}' | fields @timestamp, @message, @logStream | sort @timestamp desc | limit 50"
        }
      }
    ] : [],
    var.dashboard_include_runtime_logs ? [
      {
        type = "log"
        properties = {
          title  = "Runtime Logs"
          region = local.dashboard_region_effective
          view   = "table"
          query  = "SOURCE '/aws/bedrock/agentcore/runtime/${var.agent_name}-${var.environment}' | fields @timestamp, @message, @logStream | sort @timestamp desc | limit 50"
        }
      }
    ] : [],
    var.dashboard_include_code_interpreter_logs ? [
      {
        type = "log"
        properties = {
          title  = "Code Interpreter Logs"
          region = local.dashboard_region_effective
          view   = "table"
          query  = "SOURCE '/aws/bedrock/agentcore/code-interpreter/${var.agent_name}' | fields @timestamp, @message, @logStream | sort @timestamp desc | limit 50"
        }
      }
    ] : [],
    var.dashboard_include_browser_logs ? [
      {
        type = "log"
        properties = {
          title  = "Browser Logs"
          region = local.dashboard_region_effective
          view   = "table"
          query  = "SOURCE '/aws/bedrock/agentcore/browser/${var.agent_name}' | fields @timestamp, @message, @logStream | sort @timestamp desc | limit 50"
        }
      }
    ] : [],
    var.dashboard_include_evaluator_logs ? [
      {
        type = "log"
        properties = {
          title  = "Evaluator Logs"
          region = local.dashboard_region_effective
          view   = "table"
          query  = "SOURCE '/aws/bedrock/agentcore/evaluator/${var.agent_name}' | fields @timestamp, @message, @logStream | sort @timestamp desc | limit 50"
        }
      }
    ] : []
  )
}

locals {
  agent_dashboard_default_widgets_unpositioned = concat(local.agent_dashboard_metric_widgets, local.agent_dashboard_log_widgets)

  agent_dashboard_default_widgets = [
    for idx, widget in local.agent_dashboard_default_widgets_unpositioned :
    merge(widget, {
      x      = 0
      y      = idx * 6
      width  = 24
      height = 6
    })
  ]

  agent_dashboard_widgets = var.dashboard_widgets_override != "" ? tolist(jsondecode(var.dashboard_widgets_override)) : local.agent_dashboard_default_widgets
}

resource "aws_cloudwatch_dashboard" "agent" {
  count = var.enable_observability && var.enable_agent_dashboards ? 1 : 0

  dashboard_name = local.agent_dashboard_name_effective
  dashboard_body = jsonencode({
    widgets = local.agent_dashboard_widgets
  })
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
  filter_expression = "http.status >= 400"

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
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    GatewayId = local.gateway_id
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
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    GatewayId = local.gateway_id
  }

  tags = var.tags
}

# Note: Using AWS-managed encryption (SSE-S3/AES256) instead of customer-managed KMS
# This simplifies operations while maintaining security through AWS's default encryption

# MCP Gateway
resource "aws_bedrockagentcore_gateway" "main" {
  count = var.enable_gateway ? 1 : 0

  name = var.gateway_name != "" ? var.gateway_name : "${var.agent_name}-gateway"

  # Gateway requires a role with appropriate permissions
  role_arn = aws_iam_role.gateway[0].arn

  # Protocol configuration for MCP
  protocol_type = "MCP"

  protocol_configuration {
    mcp {
      search_type        = var.gateway_search_type
      supported_versions = var.gateway_mcp_versions
    }
  }

  # Note: Using AWS-managed encryption (no customer-managed KMS key)

  # Optional: CloudWatch logging configuration
  dynamic "logging_config" {
    for_each = var.enable_observability ? [1] : []
    content {
      cloud_watch_logs {
        log_group_name = aws_cloudwatch_log_group.gateway[0].name
        role_arn       = aws_iam_role.cloudwatch_logs[0].arn
      }
    }
  }

  depends_on = [
    aws_iam_role.gateway,
    aws_iam_role_policy.gateway
  ]

  tags = var.tags
}

# Gateway MCP Targets (Tool integration points)
resource "aws_bedrockagentcore_gateway_target" "mcp" {
  for_each = var.enable_gateway ? var.mcp_targets : {}

  name               = each.value.name
  gateway_identifier = aws_bedrockagentcore_gateway.main[0].gateway_id

  target_configuration {
    mcp {
      lambda {
        lambda_arn = each.value.lambda_arn
      }
    }
  }

  depends_on = [aws_bedrockagentcore_gateway.main]

  tags = var.tags
}

# CloudWatch Log Group for Gateway
resource "aws_cloudwatch_log_group" "gateway" {
  count = var.enable_gateway && var.enable_observability ? 1 : 0

  name              = "/aws/bedrock/agentcore/gateway/${var.agent_name}"
  retention_in_days = var.log_retention_days

  # Note: CloudWatch Logs uses AWS-managed encryption by default

  tags = var.tags

  depends_on = [aws_cloudwatch_log_resource_policy.bedrock_agentcore]
}

# CloudWatch Log Resource Policy for Bedrock AgentCore service
resource "aws_cloudwatch_log_resource_policy" "bedrock_agentcore" {
  count = var.enable_observability ? 1 : 0

  policy_name = "bedrock-agentcore-log-policy-${var.agent_name}"

  policy_text = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = [
          "logs:CreateLogDeliveryService",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

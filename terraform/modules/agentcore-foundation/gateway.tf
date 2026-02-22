# Note: Using AWS-managed encryption (SSE-S3/AES256) instead of customer-managed KMS
# This simplifies operations while maintaining security through AWS's default encryption

# MCP Gateway - Native Resource (Workstream A)
resource "aws_bedrockagentcore_gateway" "this" {
  count = var.enable_gateway ? 1 : 0

  name            = var.gateway_name != "" ? var.gateway_name : "${var.agent_name}-gateway"
  role_arn        = aws_iam_role.gateway[0].arn
  protocol_type   = "MCP"
  authorizer_type = "AWS_IAM"

  protocol_configuration {
    mcp {
      # Provider v6.33.0 native gateway currently validates search_type as SEMANTIC.
      # Preserve existing module input compatibility while forcing a provider-supported
      # value for the native path.
      search_type        = var.gateway_search_type == "HYBRID" ? "SEMANTIC" : var.gateway_search_type
      supported_versions = var.gateway_mcp_versions
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role.gateway,
    aws_iam_role_policy.gateway
  ]
}

# MCP Gateway Targets - Native Resource (Workstream A)
resource "aws_bedrockagentcore_gateway_target" "this" {
  for_each = var.enable_gateway ? var.mcp_targets : {}

  name               = each.value.name
  gateway_identifier = aws_bedrockagentcore_gateway.this[0].gateway_id

  target_configuration {
    mcp {
      lambda {
        lambda_arn = each.value.lambda_arn
        tool_schema {
          inline_payload {
            name        = "mcp_server"
            description = "MCP Protocol Server"
            input_schema {
              type = "object"
            }
          }
        }
      }
    }
  }

  # Use Gateway IAM role by default
  credential_provider_configuration {
    gateway_iam_role {}
  }

  depends_on = [aws_bedrockagentcore_gateway.this]
}
# CloudWatch Log Group for Gateway
resource "aws_cloudwatch_log_group" "gateway" {
  count = var.enable_gateway && var.enable_observability ? 1 : 0

  name              = "/aws/bedrock/agentcore/gateway/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags

  depends_on = [aws_cloudwatch_log_resource_policy.bedrock_agentcore]
}

# CloudWatch Log Resource Policy for Bedrock AgentCore service
resource "aws_cloudwatch_log_resource_policy" "bedrock_agentcore" {
  # checkov:skip=CKV_AWS_107: PutResourcePolicy requires wildcard
  # checkov:skip=CKV_AWS_108: PutResourcePolicy requires wildcard
  # checkov:skip=CKV_AWS_109: PutResourcePolicy requires wildcard
  # checkov:skip=CKV_AWS_110: PutResourcePolicy requires wildcard
  # checkov:skip=CKV_AWS_111: PutResourcePolicy requires wildcard
  count = var.enable_observability ? 1 : 0

  policy_name = "bedrock-agentcore-log-policy-${var.agent_name}"

  policy_document = jsonencode({
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
        # AWS-REQUIRED: logs:PutResourcePolicy does not support resource-level scoping
        Resource = "*"
      }
    ]
  })
}

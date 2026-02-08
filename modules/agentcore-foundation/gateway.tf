# Note: Using AWS-managed encryption (SSE-S3/AES256) instead of customer-managed KMS
# This simplifies operations while maintaining security through AWS's default encryption

# MCP Gateway - CLI-based provisioning
resource "null_resource" "gateway" {
  count = var.enable_gateway ? 1 : 0

  triggers = {
    name          = var.gateway_name != "" ? var.gateway_name : "${var.agent_name}-gateway"
    role_arn      = aws_iam_role.gateway[0].arn
    protocol_type = "MCP"
    search_type   = var.gateway_search_type
    versions      = join(",", var.gateway_mcp_versions)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating MCP Gateway..."

      aws bedrock-agentcore-control create-gateway \
        --name "${self.triggers.name}" \
        --role-arn "${self.triggers.role_arn}" \
        --protocol-type "MCP" \
        --protocol-configuration "{\"mcp\":{\"searchType\":\"${self.triggers.search_type}\",\"supportedVersions\":${jsonencode(var.gateway_mcp_versions)}}}" \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/gateway_output.json

      # Verify creation
      if [ ! -s "${path.module}/.terraform/gateway_output.json" ]; then
        echo "ERROR: Failed to create gateway"
        exit 1
      fi

      # Store Gateway ID
      GATEWAY_ID=$(jq -r '.gatewayId' < ${path.module}/.terraform/gateway_output.json)
      echo "$GATEWAY_ID" > ${path.module}/.terraform/gateway_id.txt
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.gateway,
    aws_iam_role_policy.gateway
  ]
}

# Gateway MCP Targets - CLI-based provisioning
resource "null_resource" "gateway_target" {
  for_each = var.enable_gateway ? var.mcp_targets : {}

  triggers = {
    name         = each.value.name
    lambda_arn   = each.value.lambda_arn
    gateway_name = var.gateway_name != "" ? var.gateway_name : "${var.agent_name}-gateway"
    gateway_config_hash = sha256(jsonencode({
      name        = var.gateway_name != "" ? var.gateway_name : "${var.agent_name}-gateway"
      search_type = var.gateway_search_type
      versions    = var.gateway_mcp_versions
    }))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating Gateway Target: ${each.value.name}..."

      if [ ! -f "${path.module}/.terraform/gateway_id.txt" ]; then
        echo "ERROR: Gateway ID not found. Create gateway first."
        exit 1
      fi

      GATEWAY_ID=$(cat "${path.module}/.terraform/gateway_id.txt")

      aws bedrock-agentcore-control create-gateway-target \
        --name "${each.value.name}" \
        --gateway-identifier "$GATEWAY_ID" \
        --target-configuration "{\"mcp\":{\"lambda\":{\"lambdaArn\":\"${each.value.lambda_arn}\"}}}" \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/target_${each.key}.json

      if [ ! -s "${path.module}/.terraform/target_${each.key}.json" ]; then
        echo "ERROR: Failed to create target ${each.value.name}"
        exit 1
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.gateway]
}

# Data sources for IDs
data "external" "gateway_output" {
  count      = var.enable_gateway ? 1 : 0
  program    = ["cat", "${path.module}/.terraform/gateway_output.json"]
  depends_on = [null_resource.gateway]
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

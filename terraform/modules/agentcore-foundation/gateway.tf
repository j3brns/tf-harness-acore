# Note: Using AWS-managed encryption (SSE-S3/AES256) instead of customer-managed KMS
# This simplifies operations while maintaining security through AWS's default encryption

# MCP Gateway - CLI-based provisioning with SSM Persistence Pattern (Rule 5)
resource "null_resource" "gateway" {
  count = var.enable_gateway ? 1 : 0

  triggers = {
    agent_name    = var.agent_name
    region        = var.region
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
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/gateway_output.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/gateway_output.json" ]; then
        echo "ERROR: Failed to create gateway"
        exit 1
      fi

      # Capture metadata
      GATEWAY_ID=$(jq -r '.gatewayId' < "${path.module}/.terraform/gateway_output.json")
      GATEWAY_ARN=$(jq -r '.gatewayArn' < "${path.module}/.terraform/gateway_output.json")
      GATEWAY_ENDPOINT=$(jq -r '.gatewayEndpoint' < "${path.module}/.terraform/gateway_output.json")

      # Rule 5.1: SSM Persistence Pattern
      echo "Persisting Gateway metadata to SSM..."
      aws ssm put-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/id" --value "$GATEWAY_ID" --type "String" --overwrite --region ${self.triggers.region}
      aws ssm put-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/arn" --value "$GATEWAY_ARN" --type "String" --overwrite --region ${self.triggers.region}
      aws ssm put-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/endpoint" --value "$GATEWAY_ENDPOINT" --type "String" --overwrite --region ${self.triggers.region}

      # Temporary local storage for immediate data source consumption in same plan
      echo "$GATEWAY_ID" > "${path.module}/.terraform/gateway_id.txt"
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Mandatory Destroy Provisioners
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e

      GATEWAY_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -z "$GATEWAY_ID" ]; then
        echo "WARN: Could not find Gateway ID in SSM for ${self.triggers.agent_name}, skipping AWS resource deletion"
      else
        echo "Deleting Gateway $GATEWAY_ID..."
        aws bedrock-agentcore-control delete-gateway --gateway-identifier "$GATEWAY_ID" --region ${self.triggers.region}

        echo "Cleaning up SSM parameter..."
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.gateway,
    aws_iam_role_policy.gateway
  ]
}

# Data source to read the ID from SSM (Rule 5.1)
data "aws_ssm_parameter" "gateway_id" {
  count = var.enable_gateway ? 1 : 0
  name  = "/agentcore/${var.agent_name}/gateway/id"

  depends_on = [null_resource.gateway]
}

data "aws_ssm_parameter" "gateway_arn" {
  count = var.enable_gateway ? 1 : 0
  name  = "/agentcore/${var.agent_name}/gateway/arn"

  depends_on = [null_resource.gateway]
}

data "aws_ssm_parameter" "gateway_endpoint" {
  count = var.enable_gateway ? 1 : 0
  name  = "/agentcore/${var.agent_name}/gateway/endpoint"

  depends_on = [null_resource.gateway]
}

# Gateway MCP Targets - CLI-based provisioning
resource "null_resource" "gateway_target" {
  for_each = var.enable_gateway ? var.mcp_targets : {}

  triggers = {
    agent_name = var.agent_name
    region     = var.region
    name       = each.value.name
    lambda_arn = each.value.lambda_arn
    gateway_id = var.enable_gateway ? data.aws_ssm_parameter.gateway_id[0].value : ""
    target_key = each.key
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating Gateway Target: ${self.triggers.name}..."

      aws bedrock-agentcore-control create-gateway-target \
        --name "${self.triggers.name}" \
        --gateway-identifier "${self.triggers.gateway_id}" \
        --target-configuration "{\"mcp\":{\"lambda\":{\"lambdaArn\":\"${self.triggers.lambda_arn}\"}}}" \
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/target_${self.triggers.target_key}.json"

      if [ ! -s "${path.module}/.terraform/target_${self.triggers.target_key}.json" ]; then
        echo "ERROR: Failed to create target ${self.triggers.name}"
        exit 1
      fi

      TARGET_ID=$(jq -r '.targetId' < "${path.module}/.terraform/target_${self.triggers.target_key}.json")

      # Persist Target ID
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/gateway/targets/${self.triggers.target_key}/id" \
        --value "$TARGET_ID" \
        --type "String" \
        --overwrite \
        --region ${self.triggers.region}
    EOT

    interpreter = ["bash", "-c"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      TARGET_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/targets/${self.triggers.target_key}/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$TARGET_ID" ]; then
        echo "Deleting Gateway Target $TARGET_ID..."
        aws bedrock-agentcore-control delete-gateway-target --gateway-identifier "${self.triggers.gateway_id}" --target-identifier "$TARGET_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/gateway/targets/${self.triggers.target_key}/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [null_resource.gateway]
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

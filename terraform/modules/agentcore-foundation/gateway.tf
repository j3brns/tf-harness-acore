# Note: Using AWS-managed encryption (SSE-S3/AES256) instead of customer-managed KMS
# This simplifies operations while maintaining security through AWS's default encryption

# MCP Gateway - CLI-based provisioning with SSM Persistence Pattern (Rule 5)
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
        --output json > "${path.module}/.terraform/gateway_output.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/gateway_output.json" ]; then
        echo "ERROR: Failed to create gateway"
        exit 1
      fi

      # Capture ID
      GATEWAY_ID=$(jq -r '.gatewayId' < "${path.module}/.terraform/gateway_output.json")
      
      # Rule 5.1: SSM Persistence Pattern
      echo "Persisting Gateway ID to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${var.agent_name}/gateway/id" \
        --value "$GATEWAY_ID" \
        --type "String" \
        --overwrite \
        --region ${var.region}

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
      # Capture the ID from SSM if possible, otherwise use local fallback
      # In destroy, we might not have path.module access the same way, 
      # but we can try to fetch from SSM based on naming convention
      
      GATEWAY_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.name}/gateway/id" --query "Parameter.Value" --output text --region ${var.region} 2>/dev/null)
      
      if [ -z "$GATEWAY_ID" ]; then
        echo "WARN: Could not find Gateway ID in SSM for ${self.triggers.name}, skipping AWS resource deletion"
      else
        echo "Deleting Gateway $GATEWAY_ID..."
        aws bedrock-agentcore-control delete-gateway --gateway-identifier "$GATEWAY_ID" --region ${var.region}
        
        echo "Cleaning up SSM parameter..."
        aws ssm delete-parameter --name "/agentcore/${self.triggers.name}/gateway/id" --region ${var.region}
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
# Note: This will only work on subsequent runs OR if the parameter exists.
# For the first run, we still need the data "external" or local file for outputs.
data "aws_ssm_parameter" "gateway_id" {
  count = var.enable_gateway ? 1 : 0
  name  = "/agentcore/${var.agent_name}/gateway/id"
  
  # Ensure we don't try to read it before it might be created in this run
  depends_on = [null_resource.gateway]
}

# Gateway MCP Targets - CLI-based provisioning
resource "null_resource" "gateway_target" {
  for_each = var.enable_gateway ? var.mcp_targets : {}

  triggers = {
    name         = each.value.name
    lambda_arn   = each.value.lambda_arn
    gateway_name = var.gateway_name != "" ? var.gateway_name : "${var.agent_name}-gateway"
    gateway_id   = var.enable_gateway ? data.aws_ssm_parameter.gateway_id[0].value : ""
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating Gateway Target: ${each.value.name}..."

      aws bedrock-agentcore-control create-gateway-target \
        --name "${each.value.name}" \
        --gateway-identifier "${self.triggers.gateway_id}" \
        --target-configuration "{\"mcp\":{\"lambda\":{\"lambdaArn\":\"${each.value.lambda_arn}\"}}}" \
        --region ${var.region} \
        --output json > "${path.module}/.terraform/target_${each.key}.json"

      if [ ! -s "${path.module}/.terraform/target_${each.key}.json" ]; then
        echo "ERROR: Failed to create target ${each.value.name}"
        exit 1
      fi
      
      TARGET_ID=$(jq -r '.targetId' < "${path.module}/.terraform/target_${each.key}.json")
      
      # Persist Target ID
      aws ssm put-parameter \
        --name "/agentcore/${var.agent_name}/gateway/targets/${each.key}/id" \
        --value "$TARGET_ID" \
        --type "String" \
        --overwrite \
        --region ${var.region}
    EOT

    interpreter = ["bash", "-c"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      # Try to find ID in SSM
      TARGET_ID=$(aws ssm get-parameter --name "/agentcore/${var.agent_name}/gateway/targets/${each.key}/id" --query "Parameter.Value" --output text --region ${var.region} 2>/dev/null)
      
      if [ -n "$TARGET_ID" ]; then
        echo "Deleting Gateway Target $TARGET_ID..."
        aws bedrock-agentcore-control delete-gateway-target --gateway-identifier "${self.triggers.gateway_id}" --target-identifier "$TARGET_ID" --region ${var.region}
        aws ssm delete-parameter --name "/agentcore/${var.agent_name}/gateway/targets/${each.key}/id" --region ${var.region}
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
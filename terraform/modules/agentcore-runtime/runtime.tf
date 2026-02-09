# Agent Runtime - CLI-based provisioning with SSM Persistence (Rule 5)
# Note: Native aws_bedrockagentcore_runtime resource not yet available in Terraform
# Using null_resource + local-exec pattern for CLI-based deployment

resource "null_resource" "agent_runtime" {
  count = var.enable_runtime ? 1 : 0

  triggers = {
    agent_name      = var.agent_name
    region          = var.region
    deployment_hash = local.source_hash
    config_hash     = sha256(jsonencode(var.runtime_config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating agent runtime for ${var.agent_name}..."

      # Get deployment package from S3
      DEPLOYMENT_S3_URI="s3://${local.deployment_bucket}"

      # Create runtime using AWS CLI
      aws bedrock-agentcore-control create-agent-runtime \
        --name "${var.agent_name}-runtime" \
        --agent-name "${var.agent_name}" \
        --role-arn "${var.runtime_role_arn != "" ? var.runtime_role_arn : aws_iam_role.runtime[0].arn}" \
        --artifact-s3-uri "$DEPLOYMENT_S3_URI" \
        --artifact-s3-key "${local.deployment_key}" \
        --execution-role-arn "${var.runtime_role_arn != "" ? var.runtime_role_arn : aws_iam_role.runtime[0].arn}" \
        --region ${var.region} \
        --output json > "${path.module}/.terraform/runtime_output.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/runtime_output.json" ]; then
        echo "ERROR: Failed to create runtime - no output file generated"
        exit 1
      fi

      # Check for error in output
      if grep -q '"error"' "${path.module}/.terraform/runtime_output.json"; then
        echo "ERROR: Runtime creation failed:"
        cat "${path.module}/.terraform/runtime_output.json"
        exit 1
      fi

      # Extract runtime ID
      RUNTIME_ID=$(jq -r '.runtimeId // empty' < "${path.module}/.terraform/runtime_output.json")
      
      if [ -z "$RUNTIME_ID" ]; then
        echo "ERROR: Runtime ID missing from output"
        exit 1
      fi

      # Rule 5.1: SSM Persistence
      echo "Persisting Runtime ID to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${var.agent_name}/runtime/id" \
        --value "$RUNTIME_ID" \
        --type "String" \
        --overwrite \
        --region ${var.region}

      echo "$RUNTIME_ID" > "${path.module}/.terraform/runtime_id.txt"
      echo "Agent runtime created successfully"
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Cleanup Hooks
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      RUNTIME_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/runtime/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)
      
      if [ -n "$RUNTIME_ID" ]; then
        echo "Deleting Runtime $RUNTIME_ID..."
        aws bedrock-agentcore-control delete-agent-runtime --runtime-identifier "$RUNTIME_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/runtime/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.runtime,
    null_resource.package_code
  ]
}

# Agent Memory - CLI-based provisioning
# Note: Native aws_bedrockagentcore_memory resource not yet available in Terraform

resource "null_resource" "agent_memory" {
  count = var.enable_memory ? 1 : 0

  triggers = {
    agent_name  = var.agent_name
    region      = var.region
    memory_type = var.memory_type
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Setting up agent memory for ${var.agent_name}..."

      # Short-term memory
      if [[ "${var.memory_type}" == "SHORT_TERM" || "${var.memory_type}" == "BOTH" ]]; then
        aws bedrock-agentcore-control create-memory \
          --name "${var.agent_name}-short-term-memory" \
          --agent-name "${var.agent_name}" \
          --memory-type "SHORT_TERM" \
          --storage-type "IN_MEMORY" \
          --ttl-minutes 60 \
          --region ${var.region} \
          --output json > "${path.module}/.terraform/short_term_memory.json"

        if [ ! -s "${path.module}/.terraform/short_term_memory.json" ]; then
          echo "ERROR: Failed to create short-term memory"
          exit 1
        fi
        
        ST_MEMORY_ID=$(jq -r '.memoryId' < "${path.module}/.terraform/short_term_memory.json")
        aws ssm put-parameter \
          --name "/agentcore/${var.agent_name}/memory/short-term/id" \
          --value "$ST_MEMORY_ID" \
          --type "String" \
          --overwrite \
          --region ${var.region}
      fi

      # Long-term memory
      if [[ "${var.memory_type}" == "LONG_TERM" || "${var.memory_type}" == "BOTH" ]]; then
        aws bedrock-agentcore-control create-memory \
          --name "${var.agent_name}-long-term-memory" \
          --agent-name "${var.agent_name}" \
          --memory-type "LONG_TERM" \
          --storage-type "PERSISTENT" \
          --region ${var.region} \
          --output json > "${path.module}/.terraform/long_term_memory.json"

        if [ ! -s "${path.module}/.terraform/long_term_memory.json" ]; then
          echo "ERROR: Failed to create long-term memory"
          exit 1
        fi
        
        LT_MEMORY_ID=$(jq -r '.memoryId' < "${path.module}/.terraform/long_term_memory.json")
        aws ssm put-parameter \
          --name "/agentcore/${var.agent_name}/memory/long-term/id" \
          --value "$LT_MEMORY_ID" \
          --type "String" \
          --overwrite \
          --region ${var.region}
      fi

      echo "Agent memory setup complete"
    EOT

    interpreter = ["bash", "-c"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      # Short-term memory cleanup
      ST_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/memory/short-term/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)
      if [ -n "$ST_ID" ]; then
        echo "Deleting Short-term Memory $ST_ID..."
        aws bedrock-agentcore-control delete-memory --memory-identifier "$ST_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/memory/short-term/id" --region ${self.triggers.region}
      fi
      
      # Long-term memory cleanup
      LT_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/memory/long-term/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)
      if [ -n "$LT_ID" ]; then
        echo "Deleting Long-term Memory $LT_ID..."
        aws bedrock-agentcore-control delete-memory --memory-identifier "$LT_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/memory/long-term/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    null_resource.agent_runtime
  ]
}

# Data source to read runtime output
data "external" "runtime_output" {
  count = var.enable_runtime ? 1 : 0

  program = ["cat", "${path.module}/.terraform/runtime_output.json"]

  depends_on = [null_resource.agent_runtime]
}

# Data source to read memory outputs
data "external" "memory_outputs" {
  count = var.enable_memory ? 1 : 0

  program = ["bash", "-c", <<-EOT
    if [ -f "${path.module}/.terraform/short_term_memory.json" ]; then
      cat ${path.module}/.terraform/short_term_memory.json
    else
      echo '{}'
    fi
    EOT
  ]

  depends_on = [null_resource.agent_memory]
}
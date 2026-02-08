# Agent Runtime - CLI-based provisioning
# Note: Native aws_bedrockagentcore_runtime resource not yet available in Terraform
# Using null_resource + local-exec pattern for CLI-based deployment

resource "null_resource" "agent_runtime" {
  count = var.enable_runtime ? 1 : 0

  triggers = {
    deployment_hash = local.source_hash
    config_hash     = sha256(jsonencode(var.runtime_config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating agent runtime for ${var.agent_name}..."

      # Get deployment package from S3
      DEPLOYMENT_S3_URI="s3://${local.deployment_bucket}"

      # Prepare runtime configuration
      RUNTIME_CONFIG='${jsonencode(var.runtime_config)}'

      # Create runtime using AWS CLI
      aws bedrock-agentcore-control create-agent-runtime \
        --name "${var.agent_name}-runtime" \
        --agent-name "${var.agent_name}" \
        --role-arn "${var.runtime_role_arn != "" ? var.runtime_role_arn : aws_iam_role.runtime[0].arn}" \
        --artifact-s3-uri "$DEPLOYMENT_S3_URI" \
        --artifact-s3-key "${local.deployment_key}" \
        --execution-role-arn "${var.runtime_role_arn != "" ? var.runtime_role_arn : aws_iam_role.runtime[0].arn}" \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/runtime_output.json

      # Verify runtime was created
      if [ ! -f "${path.module}/.terraform/runtime_output.json" ]; then
        echo "ERROR: Failed to create runtime - no output file generated"
        exit 1
      fi

      # Check for error in output
      if grep -q '"error"' ${path.module}/.terraform/runtime_output.json; then
        echo "ERROR: Runtime creation failed:"
        cat ${path.module}/.terraform/runtime_output.json
        exit 1
      fi

      # Store runtime ID for reference
      RUNTIME_ID=$(cat ${path.module}/.terraform/runtime_output.json | jq -r '.runtimeId // empty')
      if [ -n "$RUNTIME_ID" ]; then
        echo "$RUNTIME_ID" > ${path.module}/.terraform/runtime_id.txt
      fi

      echo "Agent runtime creation initiated (may require additional CLI commands)"
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
          --output json > ${path.module}/.terraform/short_term_memory.json

        # Verify short-term memory creation
        if [ ! -f "${path.module}/.terraform/short_term_memory.json" ]; then
          echo "ERROR: Failed to create short-term memory"
          exit 1
        fi
      fi

      # Long-term memory
      if [[ "${var.memory_type}" == "LONG_TERM" || "${var.memory_type}" == "BOTH" ]]; then
        aws bedrock-agentcore-control create-memory \
          --name "${var.agent_name}-long-term-memory" \
          --agent-name "${var.agent_name}" \
          --memory-type "LONG_TERM" \
          --storage-type "PERSISTENT" \
          --region ${var.region} \
          --output json > ${path.module}/.terraform/long_term_memory.json

        # Verify long-term memory creation
        if [ ! -f "${path.module}/.terraform/long_term_memory.json" ]; then
          echo "ERROR: Failed to create long-term memory"
          exit 1
        fi
      fi

      echo "Agent memory setup initiated"
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

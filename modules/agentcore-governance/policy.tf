# Policy Engine - CLI-based provisioning
# Note: Native aws_bedrockagentcore_policy_engine resource not yet available in Terraform

resource "null_resource" "policy_engine" {
  count = var.enable_policy_engine ? 1 : 0

  triggers = {
    schema_hash = var.policy_engine_schema != "" ? sha256(var.policy_engine_schema) : "no-schema"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating policy engine for ${var.agent_name}..."

      # Create policy engine
      aws bedrock-agentcore-control create-policy-engine \
        --name "${var.agent_name}-policy-engine" \
        %{if var.policy_engine_schema != ""}
        --schema '${var.policy_engine_schema}' \
        %{endif}
        --region ${var.region} \
        --output json > ${path.module}/.terraform/policy_engine.json

      # Verify output file exists and is not empty
      if [ ! -s "${path.module}/.terraform/policy_engine.json" ]; then
        echo "ERROR: Failed to create policy engine - no output received"
        exit 1
      fi

      # Extract policy engine ID
      POLICY_ENGINE_ID=$(jq -r '.policyEngineId // empty' < ${path.module}/.terraform/policy_engine.json)
      if [ -z "$POLICY_ENGINE_ID" ]; then
        echo "ERROR: Policy engine ID missing from output"
        exit 1
      fi

      echo "$POLICY_ENGINE_ID" > ${path.module}/.terraform/policy_engine_id.txt
      echo "Policy engine created successfully"
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.policy_engine
  ]
}

# Cedar Policies
resource "null_resource" "cedar_policies" {
  for_each = var.enable_policy_engine ? var.cedar_policy_files : {}

  triggers = {
    policy_content = filesha256(each.value)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating Cedar policy: ${each.key}..."

      # Read policy file
      POLICY_CONTENT=$(cat "${each.value}")

      # Check if policy engine exists
      if [ -f "${path.module}/.terraform/policy_engine_id.txt" ]; then
        POLICY_ENGINE_ID=$(cat ${path.module}/.terraform/policy_engine_id.txt)

        # Create policy
        aws bedrock-agentcore-control create-policy \
          --policy-engine-identifier "$POLICY_ENGINE_ID" \
          --name "${each.key}" \
          --policy-statements "$POLICY_CONTENT" \
          --region ${var.region} \
          --output json > ${path.module}/.terraform/policy_${each.key}.json

        # Verify output file
        if [ ! -s "${path.module}/.terraform/policy_${each.key}.json" ]; then
          echo "ERROR: Failed to create policy ${each.key}"
          exit 1
        fi

        echo "Policy ${each.key} created"
      else
        echo "ERROR: Policy engine ID not found. Ensure policy engine was created first."
        exit 1
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    null_resource.policy_engine
  ]
}

# CloudWatch log group for policy engine
resource "aws_cloudwatch_log_group" "policy_engine" {
  count = var.enable_policy_engine ? 1 : 0

  name              = "/aws/bedrock/agentcore/policy-engine/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# Data source to read policy engine output
data "external" "policy_engine_output" {
  count = var.enable_policy_engine ? 1 : 0

  program = ["cat", "${path.module}/.terraform/policy_engine.json"]

  depends_on = [null_resource.policy_engine]
}

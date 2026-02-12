# Policy Engine - CLI-based provisioning with SSM Persistence (Rule 5)
# Note: Native aws_bedrockagentcore_policy_engine resource not yet available in Terraform

resource "null_resource" "policy_engine" {
  count = var.enable_policy_engine ? 1 : 0

  triggers = {
    agent_name  = var.agent_name
    region      = var.region
    schema_hash = var.policy_engine_schema != "" ? sha256(var.policy_engine_schema) : "no-schema"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating policy engine for ${self.triggers.agent_name}..."

      # Create policy engine
      aws bedrock-agentcore-control create-policy-engine \
        --name "${self.triggers.agent_name}-policy-engine" \
        %{if var.policy_engine_schema != ""}
        --schema '${var.policy_engine_schema}' \
        %{endif}
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/policy_engine.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/policy_engine.json" ]; then
        echo "ERROR: Failed to create policy engine - no output received"
        exit 1
      fi

      # Extract policy engine ID
      POLICY_ENGINE_ID=$(jq -r '.policyEngineId // empty' < "${path.module}/.terraform/policy_engine.json")
      if [ -z "$POLICY_ENGINE_ID" ]; then
        echo "ERROR: Policy engine ID missing from output"
        exit 1
      fi

      # Rule 5.1: SSM Persistence
      echo "Persisting Policy Engine ID to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/policy-engine/id" \
        --value "$POLICY_ENGINE_ID" \
        --type "String" \
        --overwrite \
        --region ${self.triggers.region}

      # Local fallback for same-run consumption
      echo "$POLICY_ENGINE_ID" > "${path.module}/.terraform/policy_engine_id.txt"
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Cleanup Hooks
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      POLICY_ENGINE_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/policy-engine/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$POLICY_ENGINE_ID" ]; then
        echo "Deleting Policy Engine $POLICY_ENGINE_ID..."
        aws bedrock-agentcore-control delete-policy-engine --policy-engine-identifier "$POLICY_ENGINE_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/policy-engine/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.policy_engine
  ]
}

data "aws_ssm_parameter" "policy_engine_id" {
  count      = var.enable_policy_engine ? 1 : 0
  name       = "/agentcore/${var.agent_name}/policy-engine/id"
  depends_on = [null_resource.policy_engine]
}

# Cedar Policies
resource "null_resource" "cedar_policies" {
  for_each = var.enable_policy_engine ? var.cedar_policy_files : {}

  triggers = {
    agent_name       = var.agent_name
    region           = var.region
    policy_name      = each.key
    policy_content   = filesha256(each.value)
    policy_engine_id = var.enable_policy_engine ? data.aws_ssm_parameter.policy_engine_id[0].value : ""
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating Cedar policy: ${self.triggers.policy_name}..."

      # Read policy file
      POLICY_CONTENT=$(cat "${var.cedar_policy_files[self.triggers.policy_name]}")

      # Create policy
      aws bedrock-agentcore-control create-policy \
        --policy-engine-identifier "${self.triggers.policy_engine_id}" \
        --name "${self.triggers.policy_name}" \
        --policy-statements "$POLICY_CONTENT" \
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/policy_${self.triggers.policy_name}.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/policy_${self.triggers.policy_name}.json" ]; then
        echo "ERROR: Failed to create policy ${self.triggers.policy_name}"
        exit 1
      fi

      POLICY_ID=$(jq -r '.policyId' < "${path.module}/.terraform/policy_${self.triggers.policy_name}.json")

      # Persist Policy ID
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/policies/${self.triggers.policy_name}/id" \
        --value "$POLICY_ID" \
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
      POLICY_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/policies/${self.triggers.policy_name}/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$POLICY_ID" ]; then
        echo "Deleting Policy $POLICY_ID from Engine ${self.triggers.policy_engine_id}..."
        aws bedrock-agentcore-control delete-policy \
          --policy-engine-identifier "${self.triggers.policy_engine_id}" \
          --policy-identifier "$POLICY_ID" \
          --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/policies/${self.triggers.policy_name}/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    null_resource.policy_engine
  ]
}

# Bedrock Guardrails
resource "null_resource" "guardrail" {
  count = var.enable_guardrails ? 1 : 0

  triggers = {
    agent_name     = var.agent_name
    region         = var.region
    bedrock_region = local.bedrock_region
    name           = var.guardrail_name != "" ? var.guardrail_name : "${var.agent_name}-guardrail"
    config_hash = sha256(jsonencode({
      filters                = var.guardrail_filters
      sensitive_info_filters = var.guardrail_sensitive_info_filters
      input_msg              = var.guardrail_blocked_input_messaging
      output_msg             = var.guardrail_blocked_outputs_messaging
    }))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating Bedrock Guardrail ${self.triggers.name}..."

      # Prepare content filters JSON
      CONTENT_FILTERS=$(echo '${jsonencode([for f in var.guardrail_filters : { type = f.type, inputStrength = f.input_strength, outputStrength = f.output_strength }])}')

      # Create guardrail
      aws bedrock create-guardrail \
        --name "${self.triggers.name}" \
        --description "${var.guardrail_description}" \
        --blocked-input-messaging "${var.guardrail_blocked_input_messaging}" \
        --blocked-outputs-messaging "${var.guardrail_blocked_outputs_messaging}" \
        --content-policy "filters=$CONTENT_FILTERS" \
        --region ${self.triggers.bedrock_region} \
        --output json > "${path.module}/.terraform/guardrail.json"

      # Extract Guardrail ID
      GUARDRAIL_ID=$(jq -r '.guardrailId' < "${path.module}/.terraform/guardrail.json")

      # Create initial version
      aws bedrock create-guardrail-version \
        --guardrail-identifier "$GUARDRAIL_ID" \
        --region ${self.triggers.bedrock_region} \
        --output json > "${path.module}/.terraform/guardrail_version.json"

      VERSION=$(jq -r '.version' < "${path.module}/.terraform/guardrail_version.json")

      # Persist to SSM
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/guardrail/id" \
        --value "$GUARDRAIL_ID" \
        --type "String" \
        --overwrite \
        --region ${self.triggers.region}

      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/guardrail/version" \
        --value "$VERSION" \
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
      GUARDRAIL_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/guardrail/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$GUARDRAIL_ID" ]; then
        echo "Deleting Guardrail $GUARDRAIL_ID..."
        aws bedrock delete-guardrail --guardrail-identifier "$GUARDRAIL_ID" --region ${self.triggers.bedrock_region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/guardrail/id" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/guardrail/version" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }
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

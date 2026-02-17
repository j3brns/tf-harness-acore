# Bedrock Application Inference Profile - CLI-based provisioning with SSM Persistence (Rule 5)
# Note: Native Terraform support is not confirmed for application inference profiles.

resource "null_resource" "inference_profile" {
  count = var.enable_inference_profile ? 1 : 0

  triggers = {
    agent_name     = var.agent_name
    region         = var.region
    bedrock_region = local.bedrock_region
    profile_name   = var.inference_profile_name
    model_source   = var.inference_profile_model_source_arn
    description    = var.inference_profile_description
    tags_hash      = sha256(jsonencode(var.inference_profile_tags))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating inference profile ${self.triggers.profile_name}..."

      jq -n \
        --arg name "${self.triggers.profile_name}" \
        --arg desc "${self.triggers.description}" \
        --arg model "${self.triggers.model_source}" \
        --argjson tags '${jsonencode(var.inference_profile_tags)}' \
        '{
          inferenceProfileName: $name,
          modelSource: { copyFrom: $model }
        }
        + ( $desc | length > 0 ? { description: $desc } : {} )
        + ( ($tags | length) > 0 ? { tags: ($tags | to_entries | map({ key: .key, value: .value })) } : {} )' \
        > "${path.module}/.terraform/inference_profile_input.json"

      aws bedrock create-inference-profile \
        --cli-input-json file://"${path.module}/.terraform/inference_profile_input.json" \
        --region ${self.triggers.bedrock_region} \
        --output json > "${path.module}/.terraform/inference_profile.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/inference_profile.json" ]; then
        echo "ERROR: Failed to create inference profile - no output file generated"
        exit 1
      fi

      if grep -q '"error"' "${path.module}/.terraform/inference_profile.json"; then
        echo "ERROR: Inference profile creation failed:"
        cat "${path.module}/.terraform/inference_profile.json"
        exit 1
      fi

      INFERENCE_PROFILE_ARN=$(jq -r '.inferenceProfileArn // empty' < "${path.module}/.terraform/inference_profile.json")
      if [ -z "$INFERENCE_PROFILE_ARN" ]; then
        echo "ERROR: Inference profile ARN missing from output"
        exit 1
      fi

      # Rule 5.1: SSM Persistence
      echo "Persisting Inference Profile ARN to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/inference-profile/arn" \
        --value "$INFERENCE_PROFILE_ARN" \
        --type "String" \
        --overwrite \
        --region ${self.triggers.region}

      echo "$INFERENCE_PROFILE_ARN" > "${path.module}/.terraform/inference_profile_arn.txt"
      echo "Inference profile created successfully"
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Cleanup Hooks
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      INFERENCE_PROFILE_ARN=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/inference-profile/arn" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$INFERENCE_PROFILE_ARN" ]; then
        echo "Deleting Inference Profile $INFERENCE_PROFILE_ARN..."
        aws bedrock delete-inference-profile --inference-profile-identifier "$INFERENCE_PROFILE_ARN" --region ${self.triggers.bedrock_region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/inference-profile/arn" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }
}

data "external" "inference_profile_output" {
  count = var.enable_inference_profile ? 1 : 0

  program = ["bash", "-c", "if [ -f ${path.module}/.terraform/inference_profile.json ]; then cat ${path.module}/.terraform/inference_profile.json; else echo '{}'; fi"]

  depends_on = [null_resource.inference_profile]
}

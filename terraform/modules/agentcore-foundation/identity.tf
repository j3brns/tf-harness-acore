# Workload Identity - CLI-based provisioning with SSM Persistence Pattern (Rule 5)
resource "null_resource" "workload_identity" {
  count = var.enable_identity ? 1 : 0

  triggers = {
    agent_name = var.agent_name
    region     = var.region
    name       = "${var.agent_name}-workload-identity"
    urls       = join(",", var.oauth_return_urls)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-workload-identity \
        --name "${self.triggers.name}" \
        --allowed-resource-oauth2-return-urls ${jsonencode(var.oauth_return_urls)} \
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/identity_output.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/identity_output.json" ]; then
        echo "ERROR: Failed to create workload identity"
        exit 1
      fi

      IDENTITY_ID=$(jq -r '.workloadIdentityId' < "${path.module}/.terraform/identity_output.json")

      # Rule 5.1: SSM Persistence Pattern
      echo "Persisting Workload Identity ID to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/identity/id" \
        --value "$IDENTITY_ID" \
        --type "String" \
        --overwrite \
        --region ${self.triggers.region}
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Mandatory Destroy Provisioners
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      IDENTITY_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/identity/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$IDENTITY_ID" ]; then
        echo "Deleting Workload Identity $IDENTITY_ID..."
        aws bedrock-agentcore-control delete-workload-identity --workload-identity-identifier "$IDENTITY_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/identity/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }
}

data "external" "identity_output" {
  count      = var.enable_identity ? 1 : 0
  program    = ["cat", "${path.module}/.terraform/identity_output.json"]
  depends_on = [null_resource.workload_identity]
}

# Note: OAuth2 credential providers require CLI-based creation:
# aws bedrock-agentcore-control create-oauth2-credential-provider \
#   --name "provider-name" \
#   --workload-identity-identifier <identity-id> \
#   --client-id "your-client-id" \
#   --client-secret "your-client-secret"

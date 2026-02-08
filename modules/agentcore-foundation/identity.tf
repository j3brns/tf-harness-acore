# Workload Identity - CLI-based provisioning
resource "null_resource" "workload_identity" {
  count = var.enable_identity ? 1 : 0

  triggers = {
    name = "${var.agent_name}-workload-identity"
    urls = join(",", var.oauth_return_urls)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-workload-identity \
        --name "${self.triggers.name}" \
        --allowed-resource-oauth2-return-urls ${jsonencode(var.oauth_return_urls)} \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/identity_output.json
      
      if [ ! -s "${path.module}/.terraform/identity_output.json" ]; then
        exit 1
      fi
    EOT

    interpreter = ["bash", "-c"]
  }
}

data "external" "identity_output" {
  count = var.enable_identity ? 1 : 0
  program = ["cat", "${path.module}/.terraform/identity_output.json"]
  depends_on = [null_resource.workload_identity]
}

# Note: OAuth2 credential providers require CLI-based creation:
# aws bedrock-agentcore-control create-oauth2-credential-provider \
#   --name "provider-name" \
#   --workload-identity-identifier <identity-id> \
#   --client-id "your-client-id" \
#   --client-secret "your-client-secret"

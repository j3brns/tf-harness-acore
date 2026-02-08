# Workload Identity for Agents
resource "aws_bedrockagentcore_workload_identity" "agent" {
  count = var.enable_identity ? 1 : 0

  name = "${var.agent_name}-workload-identity"

  allowed_resource_oauth2_return_urls = var.oauth_return_urls

  tags = var.tags
}

# Note: OAuth2 credential providers require CLI-based creation:
# aws bedrock-agentcore-control create-oauth2-credential-provider \
#   --name "provider-name" \
#   --workload-identity-identifier <identity-id> \
#   --client-id "your-client-id" \
#   --client-secret "your-client-secret"

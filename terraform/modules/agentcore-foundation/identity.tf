# Workload Identity - Native Provider Resource (v6.33.0)
resource "aws_bedrockagentcore_workload_identity" "this" {
  count = var.enable_identity ? 1 : 0

  name                                = "${var.agent_name}-workload-identity"
  allowed_resource_oauth2_return_urls = var.oauth_return_urls

  tags = var.tags
}

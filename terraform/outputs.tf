output "agentcore_bff_spa_url" {
  description = "SPA URL"
  value       = module.agentcore_bff.spa_url
}

output "agentcore_bff_api_url" {
  description = "BFF API URL"
  value       = module.agentcore_bff.api_url
}

output "agentcore_bff_session_table_name" {
  description = "DynamoDB Session Table"
  value       = module.agentcore_bff.session_table_name
}

output "agentcore_bff_rest_api_id" {
  description = "REST API ID"
  value       = module.agentcore_bff.rest_api_id
}

output "agentcore_bff_authorizer_id" {
  description = "Authorizer ID"
  value       = module.agentcore_bff.authorizer_id
}

output "agentcore_runtime_arn" {
  description = "AgentCore runtime ARN"
  value       = module.agentcore_runtime.runtime_arn
}

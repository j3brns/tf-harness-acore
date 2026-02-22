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

output "agentcore_bff_audit_logs_s3_prefix" {
  description = "S3 prefix for BFF proxy audit shadow JSON logs"
  value       = module.agentcore_bff.audit_logs_s3_prefix
}

output "agentcore_bff_audit_logs_athena_database" {
  description = "Athena/Glue database for BFF proxy audit logs"
  value       = module.agentcore_bff.audit_logs_athena_database
}

output "agentcore_bff_audit_logs_athena_table" {
  description = "Athena/Glue table for BFF proxy audit logs"
  value       = module.agentcore_bff.audit_logs_athena_table
}

output "agentcore_bff_audit_logs_athena_workgroup" {
  description = "Athena workgroup for BFF proxy audit logs"
  value       = module.agentcore_bff.audit_logs_athena_workgroup
}

output "agentcore_runtime_arn" {
  description = "AgentCore runtime ARN"
  value       = module.agentcore_runtime.runtime_arn
  sensitive   = true
}

output "agentcore_gateway_arn" {
  description = "AgentCore gateway ARN (useful for cross-account target policies)"
  value       = module.agentcore_foundation.gateway_arn
  sensitive   = true
}

output "agentcore_gateway_role_arn" {
  description = "AgentCore gateway service role ARN (useful for cross-account Lambda resource policies)"
  value       = module.agentcore_foundation.gateway_role_arn
  sensitive   = true
}

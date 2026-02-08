output "gateway_id" {
  description = "ID of the MCP gateway"
  value       = var.enable_gateway ? aws_bedrockagentcore_gateway.main[0].gateway_id : null
}

output "gateway_arn" {
  description = "ARN of the MCP gateway"
  value       = var.enable_gateway ? aws_bedrockagentcore_gateway.main[0].gateway_arn : null
  sensitive   = true
}

output "gateway_endpoint" {
  description = "Endpoint URL of the MCP gateway"
  value       = var.enable_gateway ? aws_bedrockagentcore_gateway.main[0].gateway_endpoint : null
}

output "gateway_role_arn" {
  description = "IAM role ARN for the gateway"
  value       = var.enable_gateway ? aws_iam_role.gateway[0].arn : null
  sensitive   = true
}

output "workload_identity_id" {
  description = "ID of the workload identity"
  value       = var.enable_identity ? aws_bedrockagentcore_workload_identity.agent[0].workload_identity_id : null
}

output "workload_identity_arn" {
  description = "ARN of the workload identity"
  value       = var.enable_identity ? aws_bedrockagentcore_workload_identity.agent[0].workload_identity_arn : null
  sensitive   = true
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_observability ? aws_cloudwatch_log_group.agentcore[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.enable_observability ? aws_cloudwatch_log_group.agentcore[0].arn : null
}

output "kms_key_id" {
  description = "DEPRECATED: Customer-managed KMS is no longer used. AWS-managed encryption is applied."
  value       = null
}

output "kms_key_arn" {
  description = "DEPRECATED: Customer-managed KMS is no longer used. AWS-managed encryption is applied."
  value       = null
}

output "xray_sampling_rule_arn" {
  description = "ARN of the X-Ray sampling rule"
  value       = var.enable_observability && var.enable_xray ? aws_xray_sampling_rule.agentcore[0].arn : null
}

output "gateway_targets" {
  description = "Map of gateway target names to their IDs"
  value = var.enable_gateway ? {
    for name, target in aws_bedrockagentcore_gateway_target.mcp : name => {
      target_id = target.target_id
      arn       = target.target_arn
    }
  } : {}
}

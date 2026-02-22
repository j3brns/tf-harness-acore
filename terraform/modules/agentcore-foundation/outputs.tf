output "gateway_id" {
  description = "ID of the MCP gateway"
  value       = local.gateway_id
}

output "gateway_arn" {
  description = "ARN of the MCP gateway"
  value       = local.gateway_arn
  sensitive   = true
}

output "gateway_endpoint" {
  description = "Endpoint URL of the MCP gateway"
  value       = local.gateway_endpoint
}

output "gateway_role_arn" {
  description = "IAM role ARN for the gateway"
  value       = var.enable_gateway ? (var.gateway_role_arn != "" ? var.gateway_role_arn : aws_iam_role.gateway[0].arn) : null
  sensitive   = true
}

output "workload_identity_id" {
  description = "ID of the workload identity"
  value       = var.enable_identity ? data.aws_ssm_parameter.workload_identity_id[0].value : null
}

output "workload_identity_arn" {
  description = "ARN of the workload identity"
  value       = var.enable_identity ? data.aws_ssm_parameter.workload_identity_arn[0].value : null
  sensitive   = true
}

output "access_logs_bucket_id" {
  description = "Name of the S3 bucket for access logs"
  value       = var.enable_observability ? aws_s3_bucket.access_logs[0].id : null
}

output "access_logs_bucket_arn" {
  description = "ARN of the S3 bucket for access logs"
  value       = var.enable_observability ? aws_s3_bucket.access_logs[0].arn : null
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
  description = "Map of gateway target names (IDs available in .terraform/target_*.json)"
  value       = var.enable_gateway ? keys(var.mcp_targets) : []
}

output "agent_dashboard_name" {
  description = "CloudWatch dashboard name for per-agent observability"
  value       = var.enable_observability && var.enable_agent_dashboards ? aws_cloudwatch_dashboard.agent[0].dashboard_name : null
}

output "inference_profile_arn" {
  description = "ARN of the Bedrock application inference profile (null when enable_inference_profile = false)"
  value       = var.enable_inference_profile ? aws_bedrock_inference_profile.agent[0].inference_profile_arn : null
}

output "inference_profile_id" {
  description = "ID of the Bedrock application inference profile (null when enable_inference_profile = false)"
  value       = var.enable_inference_profile ? aws_bedrock_inference_profile.agent[0].inference_profile_id : null
}

output "agent_dashboard_console_url" {
  description = "CloudWatch console URL for the per-agent dashboard"
  value = var.enable_observability && var.enable_agent_dashboards ? format(
    "https://%s.console.aws.amazon.com/cloudwatch/home?region=%s#dashboards:name=%s",
    local.dashboard_region_effective,
    local.dashboard_region_effective,
    urlencode(local.agent_dashboard_name_effective)
  ) : null
}

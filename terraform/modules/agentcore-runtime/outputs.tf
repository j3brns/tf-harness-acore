output "deployment_bucket_name" {
  description = "S3 bucket name for deployment artifacts"
  value       = local.deployment_bucket
}

output "deployment_bucket_arn" {
  description = "ARN of the deployment bucket"
  value       = "arn:aws:s3:::${local.deployment_bucket}"
}

output "runtime_role_arn" {
  description = "IAM role ARN for agent runtime"
  value       = var.runtime_role_arn != "" ? var.runtime_role_arn : (var.enable_runtime ? aws_iam_role.runtime[0].arn : null)
}

output "runtime_id" {
  description = "Agent runtime ID"
  value       = var.enable_runtime ? try(data.external.runtime_output[0].result.agentRuntimeId, data.external.runtime_output[0].result.runtimeId, null) : null
  sensitive   = true
}

output "runtime_arn" {
  description = "Agent runtime ARN"
  value       = var.enable_runtime ? try(data.external.runtime_output[0].result.agentRuntimeArn, data.external.runtime_output[0].result.runtimeArn, null) : null
  sensitive   = true
}

output "short_term_memory_id" {
  description = "Short-term memory ID"
  value       = var.enable_memory && (var.memory_type == "SHORT_TERM" || var.memory_type == "BOTH") ? try(data.external.memory_outputs[0].result.memoryId, null) : null
  sensitive   = true
}

output "long_term_memory_id" {
  description = "Long-term memory ID"
  value       = var.enable_memory && (var.memory_type == "LONG_TERM" || var.memory_type == "BOTH") ? try(data.external.memory_outputs[0].result.memoryId, null) : null
  sensitive   = true
}

output "runtime_log_group_name" {
  description = "CloudWatch log group name for runtime"
  value       = var.enable_runtime ? aws_cloudwatch_log_group.runtime[0].name : null
}

output "packaging_log_group_name" {
  description = "CloudWatch log group name for packaging"
  value       = var.enable_packaging ? aws_cloudwatch_log_group.packaging[0].name : null
}

output "inference_profile_arn" {
  description = "Bedrock application inference profile ARN (passed through from agentcore-foundation)"
  value       = var.inference_profile_arn != "" ? var.inference_profile_arn : null
  sensitive   = true
}

output "source_hash" {
  description = "Hash of source code for change detection"
  value       = local.source_hash
}

output "cli_commands_required" {
  description = "Note about additional CLI commands that may be required"
  value       = var.enable_runtime ? "Runtime resources created via Terraform. Some features may require additional AWS CLI commands." : null
}

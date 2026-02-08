# ===== FOUNDATION MODULE OUTPUTS =====

output "gateway_id" {
  description = "ID of the MCP gateway"
  value       = module.agentcore_foundation.gateway_id
}

output "gateway_arn" {
  description = "ARN of the MCP gateway"
  value       = module.agentcore_foundation.gateway_arn
  sensitive   = true
}

output "gateway_endpoint" {
  description = "Endpoint URL of the MCP gateway"
  value       = module.agentcore_foundation.gateway_endpoint
}

output "gateway_targets" {
  description = "Map of gateway target IDs and ARNs"
  value       = module.agentcore_foundation.gateway_targets
}

output "workload_identity_id" {
  description = "ID of the workload identity"
  value       = module.agentcore_foundation.workload_identity_id
}

output "workload_identity_arn" {
  description = "ARN of the workload identity"
  value       = module.agentcore_foundation.workload_identity_arn
  sensitive   = true
}

output "log_group_arn" {
  description = "ARN of the main CloudWatch log group"
  value       = module.agentcore_foundation.log_group_arn
}

output "kms_key_id" {
  description = "DEPRECATED: Customer-managed KMS is no longer used. Using AWS-managed encryption."
  value       = null
}

output "xray_sampling_rule_arn" {
  description = "ARN of X-Ray sampling rule"
  value       = module.agentcore_foundation.xray_sampling_rule_arn
}

# ===== TOOLS MODULE OUTPUTS =====

output "code_interpreter_id" {
  description = "ID of the code interpreter"
  value       = module.agentcore_tools.code_interpreter_id
}

output "code_interpreter_arn" {
  description = "ARN of the code interpreter"
  value       = module.agentcore_tools.code_interpreter_arn
  sensitive   = true
}

output "browser_id" {
  description = "ID of the browser tool"
  value       = module.agentcore_tools.browser_id
}

output "browser_arn" {
  description = "ARN of the browser tool"
  value       = module.agentcore_tools.browser_arn
  sensitive   = true
}

# ===== RUNTIME MODULE OUTPUTS =====

output "deployment_bucket_name" {
  description = "S3 bucket for deployment artifacts"
  value       = module.agentcore_runtime.deployment_bucket_name
}

output "runtime_role_arn" {
  description = "IAM role ARN for agent runtime"
  value       = module.agentcore_runtime.runtime_role_arn
  sensitive   = true
}

output "runtime_id" {
  description = "Agent runtime ID"
  value       = module.agentcore_runtime.runtime_id
  sensitive   = true
}

output "short_term_memory_id" {
  description = "Short-term memory ID"
  value       = module.agentcore_runtime.short_term_memory_id
  sensitive   = true
}

output "long_term_memory_id" {
  description = "Long-term memory ID"
  value       = module.agentcore_runtime.long_term_memory_id
  sensitive   = true
}

output "source_hash" {
  description = "Source code hash for change detection"
  value       = module.agentcore_runtime.source_hash
}

# ===== GOVERNANCE MODULE OUTPUTS =====

output "policy_engine_id" {
  description = "ID of the policy engine"
  value       = module.agentcore_governance.policy_engine_id
  sensitive   = true
}

output "evaluator_id" {
  description = "ID of the evaluator"
  value       = module.agentcore_governance.evaluator_id
  sensitive   = true
}

output "cedar_policies" {
  description = "Map of Cedar policies"
  value       = module.agentcore_governance.cedar_policies
}

# ===== SUMMARY OUTPUTS =====

output "agent_summary" {
  description = "Summary of deployed agent resources"
  value = {
    name                     = var.agent_name
    region                   = var.region
    environment              = var.environment
    gateway_enabled          = var.enable_gateway
    code_interpreter_enabled = var.enable_code_interpreter
    browser_enabled          = var.enable_browser
    memory_enabled           = var.enable_memory
    policy_engine_enabled    = var.enable_policy_engine
    evaluations_enabled      = var.enable_evaluations
  }
}

output "documentation_reference" {
  description = "Reference links and commands for managing the AgentCore deployment"
  value = {
    gateway_creation     = "AWS CLI: aws bedrock-agentcore-control create-gateway --name <name>"
    runtime_creation     = "AWS CLI: aws bedrock-agentcore-control create-agent-runtime --name <name>"
    policy_creation      = "AWS CLI: aws bedrock-agentcore-control create-policy-engine --name <name>"
    evaluator_creation   = "AWS CLI: aws bedrock-agentcore-control create-evaluator --name <name>"
    logs_command         = "CloudWatch: aws logs tail /aws/bedrock/agentcore/<component> --follow"
    governance_reference = module.agentcore_governance.cli_commands_reference
  }
}

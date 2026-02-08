output "policy_engine_id" {
  description = "ID of the Cedar policy engine"
  value       = var.enable_policy_engine ? try(data.external.policy_engine_output[0].result.policyEngineId, null) : null
  sensitive   = true
}

output "policy_engine_role_arn" {
  description = "IAM role ARN for policy engine"
  value       = var.enable_policy_engine && var.policy_engine_role_arn == "" ? aws_iam_role.policy_engine[0].arn : var.policy_engine_role_arn
}

output "evaluator_id" {
  description = "ID of the custom evaluator"
  value       = var.enable_evaluations ? try(data.external.evaluator_output[0].result.evaluatorId, null) : null
  sensitive   = true
}

output "evaluator_role_arn" {
  description = "IAM role ARN for evaluator"
  value       = var.enable_evaluations && var.evaluator_role_arn == "" ? aws_iam_role.evaluator[0].arn : var.evaluator_role_arn
}

output "policy_engine_log_group_name" {
  description = "CloudWatch log group name for policy engine"
  value       = var.enable_policy_engine ? aws_cloudwatch_log_group.policy_engine[0].name : null
}

output "evaluator_log_group_name" {
  description = "CloudWatch log group name for evaluator"
  value       = var.enable_evaluations ? aws_cloudwatch_log_group.evaluator[0].name : null
}

output "cedar_policies" {
  description = "Map of Cedar policy names and their status"
  value = {
    for k, v in aws_cloudwatch_log_group.policy_engine : k => {
      name   = k
      status = "created"
    }
  }
}

output "cli_commands_reference" {
  description = "Reference for CLI commands used for governance resources"
  value       = <<-EOT
    # Policy Engine Management:
    # aws bedrock-agentcore-control create-policy-engine --name <name> --region <region>
    # aws bedrock-agentcore-control create-policy --policy-engine-identifier <id> --name <name> --policy-statements <policy>

    # Evaluator Management:
    # aws bedrock-agentcore-control create-evaluator --name <name> --evaluation-level <level> --model-id <model>
    # aws bedrock-agentcore-control start-evaluation --evaluator-identifier <id> --input-data <data>

    # Monitoring:
    # aws cloudwatch describe-alarms --alarm-names ${var.agent_name}-evaluation-errors
    # aws logs tail /aws/bedrock/agentcore/evaluator/${var.agent_name} --follow
  EOT
}

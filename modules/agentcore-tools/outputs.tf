output "code_interpreter_id" {
  description = "ID of the code interpreter"
  value       = var.enable_code_interpreter ? aws_bedrockagentcore_code_interpreter.python[0].code_interpreter_id : null
}

output "code_interpreter_arn" {
  description = "ARN of the code interpreter"
  value       = var.enable_code_interpreter ? aws_bedrockagentcore_code_interpreter.python[0].code_interpreter_arn : null
  sensitive   = true
}

output "code_interpreter_role_arn" {
  description = "IAM role ARN for the code interpreter"
  value       = var.enable_code_interpreter ? aws_iam_role.code_interpreter[0].arn : null
  sensitive   = true
}

output "browser_id" {
  description = "ID of the browser tool"
  value       = var.enable_browser ? aws_bedrockagentcore_browser.web[0].browser_id : null
}

output "browser_arn" {
  description = "ARN of the browser tool"
  value       = var.enable_browser ? aws_bedrockagentcore_browser.web[0].browser_arn : null
  sensitive   = true
}

output "browser_role_arn" {
  description = "IAM role ARN for the browser"
  value       = var.enable_browser ? aws_iam_role.browser[0].arn : null
  sensitive   = true
}

output "code_interpreter_log_group_name" {
  description = "CloudWatch log group name for code interpreter"
  value       = var.enable_code_interpreter ? aws_cloudwatch_log_group.code_interpreter[0].name : null
}

output "browser_log_group_name" {
  description = "CloudWatch log group name for browser"
  value       = var.enable_browser ? aws_cloudwatch_log_group.browser[0].name : null
}

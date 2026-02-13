# MCP Servers Module Outputs
#
# These outputs can be used directly in the main AgentCore configuration
#
# IMPORTANT: Outputs use ALIAS ARNs (not function ARNs) for:
# - Version pinning (Gateway targets specific version)
# - Rollback capability (change alias to previous version)
# - Change detection (ARN changes when code changes)

output "region" {
  description = "AWS region where MCP servers are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# S3 Tools Lambda Outputs
# -----------------------------------------------------------------------------

output "s3_tools_lambda_arn" {
  description = "ARN of the S3 tools MCP server Lambda (alias ARN for versioning)"
  value       = var.deploy_s3_tools ? aws_lambda_alias.s3_tools_live[0].arn : null
}

output "s3_tools_lambda_function_arn" {
  description = "Function ARN (not alias) - use for IAM permissions only"
  value       = var.deploy_s3_tools ? aws_lambda_function.s3_tools[0].arn : null
}

output "s3_tools_lambda_name" {
  description = "Name of the S3 tools MCP server Lambda"
  value       = var.deploy_s3_tools ? aws_lambda_function.s3_tools[0].function_name : null
}

output "s3_tools_lambda_version" {
  description = "Current deployed version of S3 tools Lambda"
  value       = var.deploy_s3_tools ? aws_lambda_function.s3_tools[0].version : null
}

# -----------------------------------------------------------------------------
# Titanic Data Lambda Outputs
# -----------------------------------------------------------------------------

output "titanic_data_lambda_arn" {
  description = "ARN of the Titanic data MCP server Lambda (alias ARN for versioning)"
  value       = var.deploy_titanic_data ? aws_lambda_alias.titanic_data_live[0].arn : null
}

output "titanic_data_lambda_function_arn" {
  description = "Function ARN (not alias) - use for IAM permissions only"
  value       = var.deploy_titanic_data ? aws_lambda_function.titanic_data[0].arn : null
}

output "titanic_data_lambda_name" {
  description = "Name of the Titanic data MCP server Lambda"
  value       = var.deploy_titanic_data ? aws_lambda_function.titanic_data[0].function_name : null
}

output "titanic_data_lambda_version" {
  description = "Current deployed version of Titanic data Lambda"
  value       = var.deploy_titanic_data ? aws_lambda_function.titanic_data[0].version : null
}

# -----------------------------------------------------------------------------
# AWS CLI Tools Lambda Outputs
# -----------------------------------------------------------------------------

output "awscli_tools_lambda_arn" {
  description = "ARN of the AWS CLI tools MCP server Lambda (alias ARN for versioning)"
  value       = var.deploy_awscli_tools ? aws_lambda_alias.awscli_tools_live[0].arn : null
}

output "awscli_tools_lambda_function_arn" {
  description = "Function ARN (not alias) - use for IAM permissions only"
  value       = var.deploy_awscli_tools ? aws_lambda_function.awscli_tools[0].arn : null
}

output "awscli_tools_lambda_name" {
  description = "Name of the AWS CLI tools MCP server Lambda"
  value       = var.deploy_awscli_tools ? aws_lambda_function.awscli_tools[0].function_name : null
}

output "awscli_tools_lambda_version" {
  description = "Current deployed version of AWS CLI tools Lambda"
  value       = var.deploy_awscli_tools ? aws_lambda_function.awscli_tools[0].version : null
}

# -----------------------------------------------------------------------------
# Shared Outputs
# -----------------------------------------------------------------------------

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.mcp_lambda.arn
}

# -----------------------------------------------------------------------------
# Ready-to-use MCP targets configuration
# -----------------------------------------------------------------------------
# Use this directly in your agentcore configuration:
#   mcp_targets = module.mcp_servers.mcp_targets
#
# The lambda_arn uses the ALIAS ARN which:
# - Changes when Lambda code changes (triggers Gateway target update)
# - Enables rollback by pointing alias to previous version
# - Provides audit trail via version numbers

output "mcp_targets" {
  description = "Ready-to-use MCP targets configuration for agentcore gateway (uses alias ARNs)"
  value = merge(
    var.deploy_s3_tools ? {
      s3_tools = {
        name        = "s3-tools"
        lambda_arn  = aws_lambda_alias.s3_tools_live[0].arn
        version     = aws_lambda_function.s3_tools[0].version
        description = "S3 bucket and object operations"
      }
    } : {},
    var.deploy_titanic_data ? {
      titanic_data = {
        name        = "titanic-data"
        lambda_arn  = aws_lambda_alias.titanic_data_live[0].arn
        version     = aws_lambda_function.titanic_data[0].version
        description = "Titanic dataset for analysis"
      }
    } : {},
    var.deploy_awscli_tools ? {
      awscli_tools = {
        name        = "awscli-tools"
        lambda_arn  = aws_lambda_alias.awscli_tools_live[0].arn
        version     = aws_lambda_function.awscli_tools[0].version
        description = "AWS CLI-like operations"
      }
    } : {}
  )
}

# -----------------------------------------------------------------------------
# Deployment Info (for debugging/audit)
# -----------------------------------------------------------------------------

output "deployment_info" {
  description = "Deployment information for audit trail"
  value = {
    s3_tools = var.deploy_s3_tools ? {
      function_name = aws_lambda_function.s3_tools[0].function_name
      version       = aws_lambda_function.s3_tools[0].version
      alias         = "live"
      alias_arn     = aws_lambda_alias.s3_tools_live[0].arn
      code_sha256   = aws_lambda_function.s3_tools[0].source_code_hash
    } : null
    titanic_data = var.deploy_titanic_data ? {
      function_name = aws_lambda_function.titanic_data[0].function_name
      version       = aws_lambda_function.titanic_data[0].version
      alias         = "live"
      alias_arn     = aws_lambda_alias.titanic_data_live[0].arn
      code_sha256   = aws_lambda_function.titanic_data[0].source_code_hash
    } : null
    awscli_tools = var.deploy_awscli_tools ? {
      function_name = aws_lambda_function.awscli_tools[0].function_name
      version       = aws_lambda_function.awscli_tools[0].version
      alias         = "live"
      alias_arn     = aws_lambda_alias.awscli_tools_live[0].arn
      code_sha256   = aws_lambda_function.awscli_tools[0].source_code_hash
    } : null
  }
}

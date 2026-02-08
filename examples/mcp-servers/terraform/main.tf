# MCP Server Deployment Module
#
# Deploys Lambda-based MCP servers for use with Bedrock AgentCore Gateway.
# Supports multiple MCP server types: s3-tools, titanic-data, custom.

terraform {
  required_version = "= 1.14.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "agentcore-mcp"
}

variable "deploy_s3_tools" {
  description = "Deploy the S3 tools MCP server"
  type        = bool
  default     = true
}

variable "deploy_titanic_data" {
  description = "Deploy the Titanic data MCP server"
  type        = bool
  default     = true
}

variable "s3_tools_allowed_buckets" {
  description = "List of S3 bucket and object ARNs the S3 tools server can access (include both bucket and bucket/*)."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.deploy_s3_tools || length(var.s3_tools_allowed_buckets) > 0
    error_message = "s3_tools_allowed_buckets must be set when deploy_s3_tools is true."
  }

  validation {
    condition = !var.deploy_s3_tools || alltrue([
      for arn in var.s3_tools_allowed_buckets :
      can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/\\*)?$", arn))
    ])
    error_message = "s3_tools_allowed_buckets must contain valid S3 bucket or object ARNs."
  }

  validation {
    condition = !var.deploy_s3_tools || alltrue([
      for base in distinct([for arn in var.s3_tools_allowed_buckets : replace(arn, "/*", "")]) :
      contains(var.s3_tools_allowed_buckets, base) && contains(var.s3_tools_allowed_buckets, "${base}/*")
    ])
    error_message = "For each bucket, include both the bucket ARN and the object ARN (bucket/*)."
  }
}

variable "enable_bedrock_agentcore_invoke_permission" {
  description = "Add explicit Lambda permissions for Bedrock AgentCore service principal (useful for cross-account or service-principal invokes)."
  type        = bool
  default     = false
}

variable "bedrock_agentcore_invoke_principal" {
  description = "Principal allowed to invoke MCP Lambda functions."
  type        = string
  default     = "bedrock-agentcore.amazonaws.com"

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.amazonaws\\.com$", var.bedrock_agentcore_invoke_principal))
    error_message = "bedrock_agentcore_invoke_principal must be a valid AWS service principal."
  }
}

variable "bedrock_agentcore_source_account" {
  description = "Optional source account for Lambda invoke permission (defaults to current account if empty)."
  type        = string
  default     = ""

  validation {
    condition     = var.bedrock_agentcore_source_account == "" || can(regex("^[0-9]{12}$", var.bedrock_agentcore_source_account))
    error_message = "bedrock_agentcore_source_account must be a 12-digit AWS account ID."
  }
}

variable "bedrock_agentcore_source_arn" {
  description = "Optional source ARN for Lambda invoke permission (e.g., Gateway ARN)."
  type        = string
  default     = ""

  validation {
    condition     = var.bedrock_agentcore_source_arn == "" || can(regex("^arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:.+$", var.bedrock_agentcore_source_arn))
    error_message = "bedrock_agentcore_source_arn must be a valid ARN."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory" {
  description = "Lambda function memory in MB"
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "mcp-servers"
  })

  s3_tools_bucket_arns = var.deploy_s3_tools ? distinct([
    for arn in var.s3_tools_allowed_buckets : replace(arn, "/*", "")
  ]) : []
  s3_tools_object_arns = var.deploy_s3_tools ? [
    for arn in local.s3_tools_bucket_arns : "${arn}/*"
  ] : []
  s3_tools_allowed_bucket_names = var.deploy_s3_tools ? distinct([
    for arn in local.s3_tools_bucket_arns : replace(arn, "arn:aws:s3:::", "")
  ]) : []

  bedrock_agentcore_source_account = var.bedrock_agentcore_source_account != "" ? var.bedrock_agentcore_source_account : data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# IAM Roles
# -----------------------------------------------------------------------------

# Base Lambda execution role
resource "aws_iam_role" "mcp_lambda" {
  name = "${var.name_prefix}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# CloudWatch Logs policy
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${var.name_prefix}-logs-policy"
  role = aws_iam_role.mcp_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"
      ]
    }]
  })
}

# S3 access policy (for S3 tools server)
resource "aws_iam_role_policy" "s3_access" {
  count = var.deploy_s3_tools ? 1 : 0
  name  = "${var.name_prefix}-s3-access-policy"
  role  = aws_iam_role.mcp_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:ListAllMyBuckets"
      ]
      # AWS-REQUIRED: s3:ListAllMyBuckets does not support resource-level scoping
      Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = local.s3_tools_bucket_arns
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:HeadObject"
        ]
        Resource = local.s3_tools_object_arns
    }]
  })
}

# -----------------------------------------------------------------------------
# Lambda: S3 Tools MCP Server
# -----------------------------------------------------------------------------
# Note: Packaging is performed by null_resource in packaging.tf (deps + code)

resource "aws_lambda_function" "s3_tools" {
  count = var.deploy_s3_tools ? 1 : 0

  filename         = "${local.build_dir}/s3-tools.zip"
  function_name    = "${var.name_prefix}-s3-tools-${var.environment}"
  role             = aws_iam_role.mcp_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = local.s3_tools_package_hash
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  # Publish versions for rollback capability
  publish = true

  environment {
    variables = {
      ENVIRONMENT     = var.environment
      LOG_LEVEL       = var.environment == "prod" ? "INFO" : "DEBUG"
      ALLOWED_BUCKETS = join(",", local.s3_tools_allowed_bucket_names)
    }
  }

  tags = local.common_tags

  depends_on = [null_resource.build_s3_tools]
}

# Lambda alias for stable ARN - Gateway references this, not $LATEST
resource "aws_lambda_alias" "s3_tools_live" {
  count = var.deploy_s3_tools ? 1 : 0

  name             = "live"
  description      = "Live version for Gateway integration"
  function_name    = aws_lambda_function.s3_tools[0].function_name
  function_version = aws_lambda_function.s3_tools[0].version
}

resource "aws_lambda_permission" "s3_tools_bedrock_invoke" {
  count = var.enable_bedrock_agentcore_invoke_permission && var.deploy_s3_tools ? 1 : 0

  statement_id   = "AllowBedrockAgentcoreInvokeS3Tools"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.s3_tools[0].function_name
  qualifier      = aws_lambda_alias.s3_tools_live[0].name
  principal      = var.bedrock_agentcore_invoke_principal
  source_account = local.bedrock_agentcore_source_account
  source_arn     = var.bedrock_agentcore_source_arn != "" ? var.bedrock_agentcore_source_arn : null
}

resource "aws_cloudwatch_log_group" "s3_tools" {
  count             = var.deploy_s3_tools ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-s3-tools-${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# Lambda: Titanic Data MCP Server
# -----------------------------------------------------------------------------
# Note: Packaging is performed by null_resource in packaging.tf (deps + code)

resource "aws_lambda_function" "titanic_data" {
  count = var.deploy_titanic_data ? 1 : 0

  filename         = "${local.build_dir}/titanic-data.zip"
  function_name    = "${var.name_prefix}-titanic-data-${var.environment}"
  role             = aws_iam_role.mcp_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = local.titanic_data_package_hash
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  # Publish versions for rollback capability
  publish = true

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  tags = local.common_tags

  depends_on = [null_resource.build_titanic_data]
}

# Lambda alias for stable ARN - Gateway references this, not $LATEST
resource "aws_lambda_alias" "titanic_data_live" {
  count = var.deploy_titanic_data ? 1 : 0

  name             = "live"
  description      = "Live version for Gateway integration"
  function_name    = aws_lambda_function.titanic_data[0].function_name
  function_version = aws_lambda_function.titanic_data[0].version
}

resource "aws_lambda_permission" "titanic_data_bedrock_invoke" {
  count = var.enable_bedrock_agentcore_invoke_permission && var.deploy_titanic_data ? 1 : 0

  statement_id   = "AllowBedrockAgentcoreInvokeTitanicData"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.titanic_data[0].function_name
  qualifier      = aws_lambda_alias.titanic_data_live[0].name
  principal      = var.bedrock_agentcore_invoke_principal
  source_account = local.bedrock_agentcore_source_account
  source_arn     = var.bedrock_agentcore_source_arn != "" ? var.bedrock_agentcore_source_arn : null
}

resource "aws_cloudwatch_log_group" "titanic_data" {
  count             = var.deploy_titanic_data ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-titanic-data-${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Outputs are defined in outputs.tf

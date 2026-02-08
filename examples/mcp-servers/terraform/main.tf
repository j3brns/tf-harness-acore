# MCP Server Deployment Module
#
# Deploys Lambda-based MCP servers for use with Bedrock AgentCore Gateway.
# Supports multiple MCP server types: s3-tools, titanic-data, custom.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
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
  description = "List of S3 bucket ARNs the S3 tools server can access (empty = all)"
  type        = list(string)
  default     = []
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

variable "enable_dependencies_layer" {
  description = "Build and attach Lambda layer with dependencies (for packages not in Lambda runtime)"
  type        = bool
  default     = false
}

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "mcp-servers"
  })
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
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation"
      ]
      Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:HeadObject"
        ]
        Resource = length(var.s3_tools_allowed_buckets) > 0 ? var.s3_tools_allowed_buckets : ["arn:aws:s3:::*"]
    }]
  })
}

# -----------------------------------------------------------------------------
# Lambda: S3 Tools MCP Server
# -----------------------------------------------------------------------------
# Note: archive_file resources are defined in packaging.tf with source_dir
# for proper directory packaging and dependency support

resource "aws_lambda_function" "s3_tools" {
  count = var.deploy_s3_tools ? 1 : 0

  filename         = data.archive_file.s3_tools[0].output_path
  function_name    = "${var.name_prefix}-s3-tools-${var.environment}"
  role             = aws_iam_role.mcp_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.s3_tools[0].output_base64sha256
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
}

# Lambda alias for stable ARN - Gateway references this, not $LATEST
resource "aws_lambda_alias" "s3_tools_live" {
  count = var.deploy_s3_tools ? 1 : 0

  name             = "live"
  description      = "Live version for Gateway integration"
  function_name    = aws_lambda_function.s3_tools[0].function_name
  function_version = aws_lambda_function.s3_tools[0].version
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
# Note: archive_file resources are defined in packaging.tf with source_dir

resource "aws_lambda_function" "titanic_data" {
  count = var.deploy_titanic_data ? 1 : 0

  filename         = data.archive_file.titanic_data[0].output_path
  function_name    = "${var.name_prefix}-titanic-data-${var.environment}"
  role             = aws_iam_role.mcp_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.titanic_data[0].output_base64sha256
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
}

# Lambda alias for stable ARN - Gateway references this, not $LATEST
resource "aws_lambda_alias" "titanic_data_live" {
  count = var.deploy_titanic_data ? 1 : 0

  name             = "live"
  description      = "Live version for Gateway integration"
  function_name    = aws_lambda_function.titanic_data[0].function_name
  function_version = aws_lambda_function.titanic_data[0].version
}

resource "aws_cloudwatch_log_group" "titanic_data" {
  count             = var.deploy_titanic_data ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-titanic-data-${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# Outputs are defined in outputs.tf

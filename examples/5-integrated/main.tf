# Integrated Example - MCP Servers + AgentCore Agent
#
# This example demonstrates the recommended pattern:
# 1. Deploy MCP servers as a submodule
# 2. Reference their outputs directly - no hardcoded ARNs
#
# Usage:
#   cd examples/5-integrated
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "bedrock-agentcore"
      Environment = var.environment
      ManagedBy   = "terraform"
      Example     = "5-integrated"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "agent_name" {
  description = "Agent name"
  type        = string
  default     = "integrated-demo"
}

# -----------------------------------------------------------------------------
# Step 1: Deploy MCP Servers
# -----------------------------------------------------------------------------

module "mcp_servers" {
  source = "../mcp-servers/terraform"

  environment         = var.environment
  name_prefix         = "agentcore-mcp"
  deploy_s3_tools     = true
  deploy_titanic_data = true

  tags = {
    Agent = var.agent_name
  }
}

# -----------------------------------------------------------------------------
# Step 2: Deploy AgentCore Agent (using MCP server outputs)
# -----------------------------------------------------------------------------

# Note: This references the main AgentCore module from the project root
# The mcp_targets use the dynamically generated ARNs from Step 1

module "agentcore" {
  source = "../../terraform" # Main terraform directory

  agent_name  = var.agent_name
  region      = var.region
  environment = var.environment

  # Foundation - Gateway with MCP targets from module output
  enable_gateway      = true
  gateway_name        = "${var.agent_name}-gateway"
  gateway_search_type = "SEMANTIC"

  # MCP targets - automatically uses correct ARNs!
  mcp_targets = module.mcp_servers.mcp_targets

  enable_identity      = false
  enable_observability = true
  enable_xray          = true

  # Tools
  enable_code_interpreter       = true
  code_interpreter_network_mode = "SANDBOX"
  enable_browser                = false

  # Runtime
  enable_runtime      = true
  runtime_source_path = "${path.module}/agent-code"
  runtime_entry_file  = "runtime.py"

  runtime_config = {
    max_iterations  = 10
    timeout_seconds = 120
  }

  enable_memory    = false
  enable_packaging = true
  python_version   = "3.12"

  # Governance
  enable_policy_engine = false
  enable_evaluations   = false

  # Frontend (BFF)
  enable_bff             = true
  oidc_issuer            = "https://example.com"
  oidc_client_id         = "test-client"
  oidc_client_secret_arn = "arn:aws:secretsmanager:${var.region}:123456789012:secret:test-secret"

  tags = {
    Example = "5-integrated"
  }

}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "agent_name" {
  description = "Deployed agent name"
  value       = var.agent_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "mcp_server_arns" {
  description = "Deployed MCP server Lambda ARNs"
  value = {
    s3_tools     = module.mcp_servers.s3_tools_lambda_arn
    titanic_data = module.mcp_servers.titanic_data_lambda_arn
  }
}

output "gateway_endpoint" {
  description = "AgentCore Gateway endpoint"
  value       = try(module.agentcore.gateway_endpoint, null)
}

output "integration_summary" {
  description = "Integration summary"
  value       = <<-EOT
    ╔══════════════════════════════════════════════════════════════╗
    ║           Integrated AgentCore Deployment                    ║
    ╠══════════════════════════════════════════════════════════════╣
    ║  Agent: ${var.agent_name}
    ║  Region: ${var.region}
    ║  Environment: ${var.environment}
    ║                                                              ║
    ║  MCP Servers Deployed:                                       ║
    ║    - s3-tools: ${module.mcp_servers.s3_tools_lambda_name}
    ║    - titanic-data: ${module.mcp_servers.titanic_data_lambda_name}
    ╚══════════════════════════════════════════════════════════════╝
  EOT
}

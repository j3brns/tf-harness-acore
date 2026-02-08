variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "agent_name" {
  description = "Name of the agent"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.agent_name))
    error_message = "Agent name must be 1-64 characters, alphanumeric and hyphens only."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ===== FOUNDATION MODULE VARIABLES =====

variable "enable_gateway" {
  description = "Enable MCP gateway for tool integration"
  type        = bool
  default     = true
}

variable "gateway_name" {
  description = "Name for the gateway"
  type        = string
  default     = ""
}

variable "gateway_search_type" {
  description = "Search type for gateway (SEMANTIC, HYBRID)"
  type        = string
  default     = "HYBRID"
}

variable "mcp_targets" {
  description = "MCP targets configuration. Use alias ARNs for version pinning and rollback capability. Recommended: use module.mcp_servers.mcp_targets output."
  type = map(object({
    name        = string
    lambda_arn  = string           # Should be alias ARN (arn:...:function:name:alias)
    version     = optional(string) # Lambda version number for audit trail
    description = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.mcp_targets :
      !can(regex("123456789012|999999999999|000000000000", v.lambda_arn))
    ])
    error_message = "Placeholder ARNs detected. Use module outputs (e.g., module.mcp_servers.mcp_targets) or real ARNs."
  }

  validation {
    condition = alltrue([
      for k, v in var.mcp_targets :
      can(regex("^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]+(:[a-zA-Z0-9_-]+)?$", v.lambda_arn))
    ])
    error_message = "Invalid Lambda ARN format. Must match: arn:aws:lambda:REGION:ACCOUNT_ID:function:NAME[:ALIAS]"
  }
}

variable "enable_identity" {
  description = "Enable workload identity"
  type        = bool
  default     = false
}

variable "oauth_return_urls" {
  description = "OAuth2 return URLs for workload identity"
  type        = list(string)
  default     = []
}

variable "enable_observability" {
  description = "Enable CloudWatch and X-Ray observability"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_xray" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "enable_kms" {
  description = "DEPRECATED: Customer-managed KMS is no longer used. AWS-managed encryption is applied by default."
  type        = bool
  default     = false
}

# ===== TOOLS MODULE VARIABLES =====

variable "enable_code_interpreter" {
  description = "Enable Python code interpreter"
  type        = bool
  default     = true
}

variable "code_interpreter_network_mode" {
  description = "Network mode for code interpreter (PUBLIC, SANDBOX, VPC)"
  type        = string
  default     = "SANDBOX"
}

variable "code_interpreter_vpc_config" {
  description = "VPC configuration for code interpreter"
  type = object({
    subnet_ids          = list(string)
    security_group_ids  = list(string)
    associate_public_ip = optional(bool, false)
  })
  default = null
}

variable "enable_browser" {
  description = "Enable web browser tool"
  type        = bool
  default     = false
}

variable "browser_network_mode" {
  description = "Network mode for browser (PUBLIC, SANDBOX, VPC)"
  type        = string
  default     = "SANDBOX"
}

variable "browser_vpc_config" {
  description = "VPC configuration for browser"
  type = object({
    subnet_ids          = list(string)
    security_group_ids  = list(string)
    associate_public_ip = optional(bool, false)
  })
  default = null
}

variable "enable_browser_recording" {
  description = "Enable session recording for browser"
  type        = bool
  default     = false
}

variable "browser_recording_s3_bucket" {
  description = "S3 bucket for browser session recordings"
  type        = string
  default     = ""
}

# ===== RUNTIME MODULE VARIABLES =====

variable "enable_runtime" {
  description = "Enable agent runtime"
  type        = bool
  default     = true
}

variable "runtime_source_path" {
  description = "Path to agent source code directory"
  type        = string
  default     = "./agent-code"
}

variable "runtime_entry_file" {
  description = "Entry point file for agent runtime"
  type        = string
  default     = "runtime.py"
}

variable "runtime_config" {
  description = "Runtime configuration as JSON"
  type        = map(any)
  default     = {}
}

variable "enable_memory" {
  description = "Enable agent memory"
  type        = bool
  default     = false
}

variable "memory_type" {
  description = "Type of memory (SHORT_TERM, LONG_TERM, or BOTH)"
  type        = string
  default     = "BOTH"
}

variable "deployment_bucket_name" {
  description = "S3 bucket name for deployment artifacts"
  type        = string
  default     = ""
}

variable "enable_s3_encryption" {
  description = "Enable S3 encryption"
  type        = bool
  default     = true
}

variable "enable_packaging" {
  description = "Enable two-stage build process"
  type        = bool
  default     = true
}

variable "python_version" {
  description = "Python version for packaging"
  type        = string
  default     = "3.12"
}

# ===== GOVERNANCE MODULE VARIABLES =====

variable "enable_policy_engine" {
  description = "Enable Cedar policy engine"
  type        = bool
  default     = false
}

variable "cedar_policy_files" {
  description = "Map of policy names to Cedar policy file paths"
  type        = map(string)
  default     = {}
}

variable "policy_engine_schema" {
  description = "Cedar schema definition for policy engine"
  type        = string
  default     = ""
}

variable "enable_evaluations" {
  description = "Enable agent evaluation system"
  type        = bool
  default     = false
}

variable "evaluation_type" {
  description = "Type of evaluations (TOOL_CALL, REASONING, RESPONSE, or ALL)"
  type        = string
  default     = "TOOL_CALL"
}

variable "evaluator_model_id" {
  description = "Model ID for evaluator"
  type        = string
  default     = "anthropic.claude-sonnet-4-5"
}

variable "evaluation_prompt" {
  description = "Prompt for agent evaluator"
  type        = string
  default     = "Evaluate the agent's response for correctness and relevance."
}

variable "evaluation_criteria" {
  description = "Evaluation criteria as JSON"
  type        = map(string)
  default     = {}
}

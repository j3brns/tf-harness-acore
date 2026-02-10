variable "agent_name" {
  description = "Name of the agent"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "bedrock_region" {
  description = "Optional Bedrock region override (defaults to region)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Gateway configuration
variable "enable_gateway" {
  description = "Enable MCP gateway"
  type        = bool
  default     = true
}

variable "gateway_name" {
  description = "Name for the gateway"
  type        = string
  default     = ""
}

variable "gateway_role_arn" {
  description = "IAM role ARN for the gateway (if not provided, one will be created)"
  type        = string
  default     = ""
}

# Encryption configuration
variable "enable_kms" {
  description = "Enable KMS encryption for logs and artifacts (Note: Managed encryption preferred)"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption (required if enable_kms is true)"
  type        = string
  default     = ""
}

variable "mcp_targets" {
  description = "MCP targets configuration. Use alias ARNs (not function ARNs) for version pinning and rollback capability."
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
    error_message = "Placeholder account IDs detected in lambda_arn. Use module outputs (e.g., module.mcp_servers.mcp_targets) or real ARNs."
  }
}

variable "gateway_search_type" {
  description = "Search type for gateway (SEMANTIC, HYBRID)"
  type        = string
  default     = "HYBRID"

  validation {
    condition     = contains(["SEMANTIC", "HYBRID"], var.gateway_search_type)
    error_message = "Search type must be SEMANTIC or HYBRID."
  }
}

variable "gateway_mcp_versions" {
  description = "Supported MCP versions"
  type        = list(string)
  default     = ["2025-03-26"]
}

# Identity configuration
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

# Observability configuration
variable "enable_observability" {
  description = "Enable CloudWatch and X-Ray observability"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch value."
  }
}

variable "enable_xray" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "xray_sampling_rate" {
  description = "X-Ray sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.1

  validation {
    condition     = var.xray_sampling_rate >= 0.0 && var.xray_sampling_rate <= 1.0
    error_message = "X-Ray sampling rate must be between 0.0 and 1.0."
  }
}

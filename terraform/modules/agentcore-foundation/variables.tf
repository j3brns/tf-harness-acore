variable "agent_name" {
  description = "Internal agent identity used in physical AWS resource names (immutable)"
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
  description = "Tags to apply to all resources. The root module always merges canonical tags (AppID, AgentAlias, Environment, AgentName, ManagedBy, Owner) before passing this value."
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

variable "oidc_issuer" {
  description = "OIDC Issuer URL for custom JWT authorizer"
  type        = string
  default     = ""
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

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "enable_agent_dashboards" {
  description = "Enable per-agent CloudWatch dashboard creation"
  type        = bool
  default     = false
}

variable "agent_dashboard_name" {
  description = "Optional CloudWatch dashboard name override (defaults to <agent_name>-dashboard when empty)"
  type        = string
  default     = ""

  validation {
    condition     = length(trimspace(var.agent_dashboard_name)) <= 255
    error_message = "agent_dashboard_name must be 255 characters or fewer."
  }
}

variable "dashboard_region" {
  description = "Optional region override for dashboard widgets and console URL hint (defaults to region when empty)"
  type        = string
  default     = ""
}

variable "dashboard_widgets_override" {
  description = "Optional JSON array string of CloudWatch dashboard widgets to replace the default widget set"
  type        = string
  default     = ""

  validation {
    condition     = var.dashboard_widgets_override == "" ? true : can(tolist(jsondecode(var.dashboard_widgets_override)))
    error_message = "dashboard_widgets_override must be an empty string or a JSON array string of widget objects."
  }
}

variable "dashboard_include_runtime_logs" {
  description = "Include runtime log widgets in the default dashboard"
  type        = bool
  default     = false
}

variable "dashboard_include_code_interpreter_logs" {
  description = "Include code interpreter log widgets in the default dashboard"
  type        = bool
  default     = false
}

variable "dashboard_include_browser_logs" {
  description = "Include browser log widgets in the default dashboard"
  type        = bool
  default     = false
}

variable "dashboard_include_evaluator_logs" {
  description = "Include evaluator log widgets in the default dashboard"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Enable WAF protection for API Gateway"
  type        = bool
  default     = false
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

variable "xray_sampling_priority" {
  description = "X-Ray sampling rule priority (1-9999). Assign unique values per agent when multiple agents share an account to avoid tie-breaking by rule name."
  type        = number
  default     = 100

  validation {
    condition     = var.xray_sampling_priority >= 1 && var.xray_sampling_priority <= 9999
    error_message = "xray_sampling_priority must be between 1 and 9999."
  }
}

# Bedrock application inference profile
variable "enable_inference_profile" {
  description = "Create a Bedrock application inference profile and scope IAM policies to its ARN instead of foundation-model/*"
  type        = bool
  default     = false
}

variable "inference_profile_name" {
  description = "Name for the Bedrock application inference profile"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_inference_profile ? length(trimspace(var.inference_profile_name)) > 0 : true
    error_message = "inference_profile_name must be set when enable_inference_profile is true."
  }
}

variable "inference_profile_model_source_arn" {
  description = "Foundation model or system-defined inference profile ARN that the application profile wraps"
  type        = string
  default     = ""

  validation {
    condition = var.enable_inference_profile ? can(
      regex(
        "^arn:aws[a-z-]*:bedrock:[a-z0-9-]+:(?:[0-9]{12})?:(foundation-model|inference-profile)/[A-Za-z0-9._:-]+$",
        var.inference_profile_model_source_arn
      )
    ) : true
    error_message = "inference_profile_model_source_arn must be a valid Bedrock foundation model or inference profile ARN."
  }
}

variable "inference_profile_description" {
  description = "Optional description for the inference profile"
  type        = string
  default     = ""

  validation {
    condition     = length(var.inference_profile_description) <= 200
    error_message = "inference_profile_description must be 200 characters or fewer."
  }
}

variable "inference_profile_tags" {
  description = "Additional tags to apply to the inference profile (merged with var.tags)"
  type        = map(string)
  default     = {}
}

variable "manage_log_resource_policy" {
  description = "Create the account-level CloudWatch log resource policy for Bedrock AgentCore. AWS allows a maximum of 10 per account/region. Set to false for every agent after the first in the same account/environment — the shared policy already covers all agents."
  type        = bool
  default     = true
}

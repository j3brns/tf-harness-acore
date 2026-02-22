variable "region" {
  description = "Default AWS region"
  type        = string
  default     = "us-east-1"
}

variable "agentcore_region" {
  description = "Optional AgentCore control-plane region override (defaults to region)"
  type        = string
  default     = ""
}

variable "bedrock_region" {
  description = "Optional Bedrock region override for model-related resources (defaults to agentcore_region)"
  type        = string
  default     = ""
}

variable "bff_region" {
  description = "Optional BFF/API Gateway region override (defaults to agentcore_region)"
  type        = string
  default     = ""
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
  description = "Internal agent identity used in physical AWS resource names (immutable). Use app_id for the human-facing alias."
  type        = string

  validation {
    condition = (
      length(var.agent_name) <= 64 &&
      (
        can(regex("^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+(?:-[a-z0-9]+)?-[a-z0-9]{4,6}$", var.agent_name)) ||
        (
          var.allow_legacy_agent_name &&
          can(regex("^[A-Za-z0-9-]{1,64}$", var.agent_name))
        )
      )
    )
    error_message = "agent_name must be lowercase and follow '<word>-<word>-<word>-<suffix>' or '<word>-<word>-<word>-<env>-<suffix>' (suffix 4-6 chars), e.g. 'research-agent-core-a1b2'. Set allow_legacy_agent_name=true only to preserve an existing deployed name. Use app_id for the human-facing alias."
  }
}

variable "app_id" {
  description = "Human-facing application alias for routing and multi-tenant isolation (North anchor). Defaults to agent_name."
  type        = string
  default     = ""
}

variable "allow_legacy_agent_name" {
  description = "Temporary migration escape hatch. Set true only to preserve an already-deployed legacy agent_name during transition to the ADR 0012 naming convention."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources. Canonical tags (AppID, AgentAlias, Environment, AgentName, ManagedBy, Owner) are always merged by the root module; values here supplement or override non-canonical keys only."
  type        = map(string)
  default     = {}
}

variable "owner" {
  description = "Owner identifier for resource tagging (team name, individual, or app ID). Applied as the Owner canonical tag. Defaults to app_id (or agent_name) when empty."
  type        = string
  default     = ""
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

variable "gateway_role_arn" {
  description = "IAM role ARN for the gateway (if not provided, one will be created)"
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

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "enable_agent_dashboards" {
  description = "Enable Terraform-managed per-agent CloudWatch dashboards"
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
  description = "Optional dashboard widget/console region override (defaults to region when empty)"
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

# ===== OBSERVABILITY SCALING VARIABLES =====

variable "xray_sampling_priority" {
  description = "X-Ray sampling rule priority (1-9999). Assign unique values per agent when multiple agents share an account to ensure deterministic sampling order."
  type        = number
  default     = 100

  validation {
    condition     = var.xray_sampling_priority >= 1 && var.xray_sampling_priority <= 9999
    error_message = "xray_sampling_priority must be between 1 and 9999."
  }
}

variable "manage_log_resource_policy" {
  description = "Create the account-level CloudWatch log resource policy for Bedrock AgentCore. AWS allows a maximum of 10 per account/region. Set to false for every agent after the first in the same account/environment — the shared policy covers all agents."
  type        = bool
  default     = true
}

# ===== SECURITY BATCH 3 VARIABLES =====

variable "enable_waf" {
  description = "Enable WAF protection for API Gateway"
  type        = bool
  default     = false
}

variable "proxy_reserved_concurrency" {
  description = "Reserved concurrent executions for the BFF proxy Lambda"
  type        = number
  default     = 10
}

variable "runtime_reserved_concurrency" {
  description = "Reserved concurrent executions for the agent runtime Lambda"
  type        = number
  default     = 10
}

variable "enable_kms" {
  description = "Enable KMS encryption for logs and artifacts"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = ""
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

variable "runtime_role_arn" {
  description = "IAM role ARN for agent runtime"
  type        = string
  default     = ""
}

variable "runtime_policy_arns" {
  description = "Additional IAM policy ARNs to attach to runtime role"
  type        = list(string)
  default     = []
}

variable "runtime_inline_policies" {
  description = "Inline policies to attach to runtime role"
  type        = map(string)
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

# Bedrock inference profiles
variable "enable_inference_profile" {
  description = "Enable Bedrock application inference profile creation"
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
  description = "Model source ARN (foundation model ARN or system-defined inference profile ARN)"
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
  description = "Tags to apply to the inference profile"
  type        = map(string)
  default     = {}
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

variable "lambda_architecture" {
  description = "Architecture for agent runtime Lambda (x86_64, arm64)"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Architecture must be x86_64 or arm64."
  }
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

variable "policy_engine_role_arn" {
  description = "IAM role ARN for policy engine"
  type        = string
  default     = ""
}

variable "enable_guardrails" {
  description = "Enable Bedrock Guardrails"
  type        = bool
  default     = false
}

variable "guardrail_name" {
  description = "Name of the guardrail"
  type        = string
  default     = ""
}

variable "guardrail_description" {
  description = "Description of the guardrail"
  type        = string
  default     = "AgentCore Bedrock Guardrail"
}

variable "guardrail_blocked_input_messaging" {
  description = "Message to return when input is blocked by guardrail"
  type        = string
  default     = "I'm sorry, I cannot process this request due to safety policies."
}

variable "guardrail_blocked_outputs_messaging" {
  description = "Message to return when output is blocked by guardrail"
  type        = string
  default     = "I'm sorry, I cannot provide a response due to safety policies."
}

variable "guardrail_filters" {
  description = "Content filters for the guardrail"
  type = list(object({
    type            = string # HATE, INSULT, SEXUAL, VIOLENCE, MISCONDUCT, PROMPT_ATTACK
    input_strength  = string # NONE, LOW, MEDIUM, HIGH
    output_strength = string # NONE, LOW, MEDIUM, HIGH
  }))
  default = [
    { type = "HATE", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "INSULT", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "SEXUAL", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "VIOLENCE", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "MISCONDUCT", input_strength = "HIGH", output_strength = "HIGH" },
    { type = "PROMPT_ATTACK", input_strength = "HIGH", output_strength = "NONE" }
  ]
}

variable "guardrail_sensitive_info_filters" {
  description = "Sensitive information filters (PII)"
  type = list(object({
    type   = string # EMAIL, ADDRESS, PHONE, etc.
    action = string # BLOCK, ANONYMIZE
  }))
  default = []
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

variable "evaluator_role_arn" {
  description = "IAM role ARN for evaluator"
  type        = string
  default     = ""
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

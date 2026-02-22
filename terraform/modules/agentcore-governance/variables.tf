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

variable "tags" {
  description = "Tags to apply to all resources. The root module always merges canonical tags (AppID, AgentAlias, Environment, AgentName, ManagedBy, Owner) before passing this value."
  type        = map(string)
  default     = {}
}

# Policy Engine configuration
variable "enable_policy_engine" {
  description = "Enable Cedar policy engine"
  type        = bool
  default     = false
}

variable "cedar_policy_files" {
  description = "Map of policy names to Cedar policy file paths"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.cedar_policy_files :
      can(regex("^[a-zA-Z0-9_-]+$", k))
    ])
    error_message = "Policy names must be alphanumeric with hyphens and underscores only."
  }
}

variable "policy_engine_schema" {
  description = "Cedar schema definition for policy engine"
  type        = string
  default     = ""
}

# Bedrock Guardrails configuration
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

# Evaluations configuration
variable "enable_evaluations" {
  description = "Enable agent evaluation system"
  type        = bool
  default     = false
}

variable "evaluation_type" {
  description = "Type of evaluations (TOOL_CALL, REASONING, RESPONSE, or ALL)"
  type        = string
  default     = "TOOL_CALL"

  validation {
    condition     = contains(["TOOL_CALL", "REASONING", "RESPONSE", "ALL"], var.evaluation_type)
    error_message = "Evaluation type must be TOOL_CALL, REASONING, RESPONSE, or ALL."
  }
}

variable "evaluator_model_id" {
  description = "Model ID for evaluator (e.g., anthropic.claude-sonnet-4-5)"
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

# Monitoring and logging
variable "enable_evaluation_monitoring" {
  description = "Enable CloudWatch monitoring for evaluations"
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

# IAM configuration
variable "policy_engine_role_arn" {
  description = "IAM role ARN for policy engine (if not provided, one will be created)"
  type        = string
  default     = ""
}

variable "evaluator_role_arn" {
  description = "IAM role ARN for evaluator (if not provided, one will be created)"
  type        = string
  default     = ""
}

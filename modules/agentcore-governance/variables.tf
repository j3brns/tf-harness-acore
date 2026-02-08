variable "agent_name" {
  description = "Name of the agent"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
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

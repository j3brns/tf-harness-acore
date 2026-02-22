# --- BFF Configuration ---

variable "enable_bff" {
  description = "Enable the Serverless SPA/BFF module"
  type        = bool
  default     = false
}

variable "enable_bff_audit_log_persistence" {
  description = "Persist BFF proxy shadow audit logs to S3 and provision Athena/Glue query resources"
  type        = bool
  default     = false
}

variable "oidc_issuer" {
  description = "OIDC Issuer URL"
  type        = string
  default     = ""
}

variable "oidc_authorization_endpoint" {
  description = "Override OIDC authorization endpoint (discovers if empty)"
  type        = string
  default     = ""
}

variable "oidc_token_endpoint" {
  description = "Override OIDC token endpoint (discovers if empty)"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC Client ID"
  type        = string
  default     = ""
}

variable "oidc_client_secret_arn" {
  description = "Secrets Manager ARN for OIDC Client Secret"
  type        = string
  default     = ""
}

variable "bff_agentcore_runtime_arn" {
  description = "AgentCore runtime ARN for the BFF proxy (required if enable_bff is true and enable_runtime is false)"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_bff ? (var.enable_runtime || length(trim(var.bff_agentcore_runtime_arn)) > 0) : true
    error_message = "bff_agentcore_runtime_arn must be set when enable_bff is true and enable_runtime is false."
  }
}

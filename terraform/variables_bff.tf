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

variable "enable_bff_cloudfront_access_logging" {
  description = "Enable CloudFront standard access logging for the BFF distribution"
  type        = bool
  default     = true
}

variable "bff_cloudfront_access_logs_prefix" {
  description = "S3 key prefix for BFF CloudFront standard access logs (no leading slash)"
  type        = string
  default     = "cloudfront-access-logs/"

  validation {
    condition = (
      trimspace(var.bff_cloudfront_access_logs_prefix) != "" &&
      !startswith(trimspace(var.bff_cloudfront_access_logs_prefix), "/")
    )
    error_message = "bff_cloudfront_access_logs_prefix must be non-empty and must not start with '/'."
  }
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

variable "bff_custom_domain_name" {
  description = "Custom domain name for the BFF CloudFront distribution (e.g., agent.example.com). Requires bff_acm_certificate_arn."
  type        = string
  default     = ""
}

variable "bff_acm_certificate_arn" {
  description = "ARN of the ACM certificate for the custom domain. Must be in us-east-1 for CloudFront."
  type        = string
  default     = ""
  validation {
    condition     = var.bff_acm_certificate_arn == "" || can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[a-f0-9-]+$", var.bff_acm_certificate_arn))
    error_message = "bff_acm_certificate_arn must be in us-east-1 for CloudFront."
  }
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

variable "bff_agentcore_runtime_role_arn" {
  description = "Optional runtime IAM role ARN for the BFF proxy to assume (set for cross-account runtime identity propagation)"
  type        = string
  default     = ""

  validation {
    condition = var.bff_agentcore_runtime_role_arn == "" || can(
      regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.bff_agentcore_runtime_role_arn)
    )
    error_message = "bff_agentcore_runtime_role_arn must be empty or a valid IAM role ARN."
  }
}

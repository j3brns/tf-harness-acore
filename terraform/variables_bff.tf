# --- BFF Configuration ---

variable "enable_bff" {
  description = "Enable the Serverless SPA/BFF module"
  type        = bool
  default     = false
}

variable "oidc_issuer" {
  description = "OIDC Issuer URL"
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

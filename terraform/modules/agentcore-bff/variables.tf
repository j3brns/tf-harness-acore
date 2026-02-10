variable "agent_name" {
  description = "Unique name for the agent application"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
}

variable "agentcore_region" {
  description = "Optional AgentCore region override for Bedrock Agent runtime calls (defaults to region)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}

# --- BFF Configuration ---

variable "enable_bff" {
  description = "Enable the Serverless SPA/BFF module"
  type        = bool
  default     = false
}

variable "spa_bucket_name" {
  description = "Name of the S3 bucket to host the SPA assets"
  type        = string
  default     = "" # Generated if empty
}

variable "oidc_issuer" {
  description = "OIDC Issuer URL (e.g., https://login.microsoftonline.com/...)"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC Client ID"
  type        = string
  default     = ""
}

variable "oidc_client_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the OIDC Client Secret"
  type        = string
  default     = ""
}

variable "session_ttl_seconds" {
  description = "DynamoDB session TTL in seconds"
  type        = number
  default     = 3600 # 1 hour
}

# --- Integration ---

variable "agent_gateway_id" {
  description = "ID of the AgentCore Gateway to proxy requests to"
  type        = string
  default     = ""
}

variable "agent_name" {
  description = "Internal agent identity used in physical AWS resource names (immutable)"
  type        = string
}

variable "app_id" {
  description = "Human-facing application alias for multi-tenant isolation"
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

variable "agentcore_runtime_arn" {
  description = "AgentCore runtime ARN to invoke"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources. The root module always merges canonical tags (AppID, Environment, AgentName, ManagedBy, Owner) before passing this value."
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

variable "logging_bucket_id" {
  description = "Optional S3 bucket ID for access logs"
  type        = string
  default     = ""
}

variable "enable_audit_log_persistence" {
  description = "Persist BFF proxy audit shadow JSON to S3 and provision Athena/Glue metadata"
  type        = bool
  default     = false
}

variable "oidc_issuer" {
  description = "OIDC Issuer URL (e.g., https://login.microsoftonline.com/...)"
  type        = string
  default     = ""
}

variable "oidc_authorization_endpoint" {
  description = "Discovered OIDC authorization endpoint"
  type        = string
  default     = ""
}

variable "oidc_token_endpoint" {
  description = "Discovered OIDC token endpoint"
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

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions for the Lambda functions"
  type        = number
  default     = -1 # Unlimited by default
}

variable "waf_acl_arn" {
  description = "ARN of the WAF Web ACL to associate with API Gateway (REGIONAL scope)"
  type        = string
  default     = ""
}

variable "custom_domain_name" {
  description = "Custom domain name for the CloudFront distribution"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM Certificate ARN for the custom domain (must be in us-east-1)"
  type        = string
  default     = ""
}

variable "cloudfront_waf_acl_arn" {
  description = "ARN of a WAFv2 Web ACL (CLOUDFRONT scope, must be in us-east-1) to associate with the CloudFront distribution. Leave empty to disable WAF on CloudFront (default). Required format: arn:aws:wafv2:us-east-1:<account>:global/webacl/<name>/<id>."
  type        = string
  default     = ""
  validation {
    condition     = var.cloudfront_waf_acl_arn == "" || can(regex("^arn:aws:wafv2:us-east-1:[0-9]{12}:global/webacl/[^/]+/[^/]+$", var.cloudfront_waf_acl_arn))
    error_message = "cloudfront_waf_acl_arn must be empty or a valid WAFv2 CLOUDFRONT-scope ARN in us-east-1, e.g. arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-acl/abc123."
  }
}

variable "agentcore_runtime_role_arn" {
  description = "IAM role ARN of the agent runtime to assume"
  type        = string
  default     = ""
}

variable "deployment_bucket_name" {
  description = "Name of the agent runtime deployment S3 bucket. Used to scope the session policy in the proxy Lambda so it references the specific bucket rather than a wildcard pattern."
  type        = string
  default     = ""
}

# --- Integration ---

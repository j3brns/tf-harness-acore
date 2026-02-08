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

# Runtime configuration
variable "enable_runtime" {
  description = "Enable agent runtime creation"
  type        = bool
  default     = true
}

variable "runtime_source_path" {
  description = "Path to agent source code directory"
  type        = string
}

variable "runtime_entry_file" {
  description = "Entry point file for agent runtime (e.g., runtime.py)"
  type        = string
  default     = "runtime.py"
}

variable "runtime_config" {
  description = "Runtime configuration as JSON"
  type        = map(any)
  default     = {}
}

# Memory configuration
variable "enable_memory" {
  description = "Enable agent memory (short-term and long-term)"
  type        = bool
  default     = false
}

variable "memory_type" {
  description = "Type of memory to enable (SHORT_TERM, LONG_TERM, or BOTH)"
  type        = string
  default     = "BOTH"

  validation {
    condition     = contains(["SHORT_TERM", "LONG_TERM", "BOTH"], var.memory_type)
    error_message = "Memory type must be SHORT_TERM, LONG_TERM, or BOTH."
  }
}

# S3 deployment configuration
variable "deployment_bucket_name" {
  description = "S3 bucket name for deployment artifacts"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable S3 versioning for deployment bucket"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 encryption for deployment bucket"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "DEPRECATED: Customer-managed KMS is no longer used. AWS-managed encryption is applied."
  type        = string
  default     = ""
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

# IAM role configuration
variable "runtime_role_arn" {
  description = "IAM role ARN for agent runtime (if not provided, one will be created)"
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

# Packaging configuration
variable "enable_packaging" {
  description = "Enable two-stage build process for dependencies"
  type        = bool
  default     = true
}

variable "python_version" {
  description = "Python version for packaging (e.g., 3.11, 3.12)"
  type        = string
  default     = "3.12"
}

variable "package_cache_ttl_hours" {
  description = "TTL in hours for dependency package cache"
  type        = number
  default     = 24

  validation {
    condition     = var.package_cache_ttl_hours > 0
    error_message = "Cache TTL must be positive."
  }
}

variable "agent_name" {
  description = "Name of the agent"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "bedrock_region" {
  description = "Optional Bedrock region override (defaults to region)"
  type        = string
  default     = ""
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
  description = "Entry point file for agent runtime"
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

# Inference profile configuration (Bedrock)
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
    condition     = var.enable_inference_profile ? length(trim(var.inference_profile_name)) > 0 : true
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

# S3 deployment configuration
variable "deployment_bucket_name" {
  description = "S3 bucket name for deployment artifacts"
  type        = string
  default     = ""
}

variable "logging_bucket_id" {
  description = "Optional S3 bucket ID for access logs"
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

variable "proxy_role_arn" {
  description = "IAM role ARN of the BFF proxy to allow role assumption"
  type        = string
  default     = ""
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions for the agent runtime"
  type        = number
  default     = -1
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

variable "enable_observability" {
  description = "Enable observability features"
  type        = bool
  default     = true
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

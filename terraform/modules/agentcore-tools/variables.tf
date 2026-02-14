variable "agent_name" {
  description = "Name of the agent"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Code Interpreter configuration
variable "enable_code_interpreter" {
  description = "Enable Python code interpreter"
  type        = bool
  default     = true
}

variable "code_interpreter_network_mode" {
  description = "Network mode for code interpreter (PUBLIC, SANDBOX, VPC)"
  type        = string
  default     = "SANDBOX"

  validation {
    condition     = contains(["PUBLIC", "SANDBOX", "VPC"], var.code_interpreter_network_mode)
    error_message = "Network mode must be PUBLIC, SANDBOX, or VPC."
  }

  validation {
    condition = var.code_interpreter_network_mode != "VPC" || (
      var.code_interpreter_vpc_config != null &&
      length(var.code_interpreter_vpc_config.subnet_ids) > 0 &&
      length(var.code_interpreter_vpc_config.security_group_ids) > 0
    )
    error_message = "VPC network mode requires code_interpreter_vpc_config with subnet_ids and security_group_ids."
  }
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

# Browser configuration
variable "enable_browser" {
  description = "Enable web browser tool"
  type        = bool
  default     = false
}

variable "browser_network_mode" {
  description = "Network mode for browser (PUBLIC, SANDBOX, VPC)"
  type        = string
  default     = "SANDBOX"

  validation {
    condition     = contains(["PUBLIC", "SANDBOX", "VPC"], var.browser_network_mode)
    error_message = "Network mode must be PUBLIC, SANDBOX, or VPC."
  }

  validation {
    condition = var.browser_network_mode != "VPC" || (
      var.browser_vpc_config != null &&
      length(var.browser_vpc_config.subnet_ids) > 0 &&
      length(var.browser_vpc_config.security_group_ids) > 0
    )
    error_message = "VPC network mode requires browser_vpc_config with subnet_ids and security_group_ids."
  }
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

variable "browser_recording_s3_prefix" {
  description = "S3 prefix for browser session recordings"
  type        = string
  default     = "browser-sessions/"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Encryption configuration
# Note: Customer-managed KMS is deprecated in favor of AWS-managed encryption.
variable "enable_kms" {
  description = "DEPRECATED: Use AWS-managed encryption."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "DEPRECATED: Use AWS-managed encryption."
  type        = string
  default     = ""
}

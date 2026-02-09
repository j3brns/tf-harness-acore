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

variable "code_interpreter_execution_timeout" {
  description = "Execution timeout in seconds for code interpreter"
  type        = number
  default     = 300

  validation {
    condition     = var.code_interpreter_execution_timeout > 0 && var.code_interpreter_execution_timeout <= 3600
    error_message = "Execution timeout must be between 1 and 3600 seconds."
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

# KMS encryption
variable "enable_kms" {
  description = "Enable KMS encryption"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption"
  type        = string
  default     = ""

  validation {
    condition = !var.enable_kms || (
      var.kms_key_arn != "" &&
      !can(regex("123456789012|999999999999|000000000000", var.kms_key_arn))
    )
    error_message = "kms_key_arn must be set to a real ARN when enable_kms is true."
  }
}

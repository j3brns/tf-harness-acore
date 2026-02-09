# TFLint Configuration for Bedrock AgentCore Terraform
#
# Run: tflint --recursive
# Init: tflint --init

config {
  # Enable all available rules by default
  call_module_type = "all"
  force = false
  disabled_by_default = false
}

# AWS Plugin
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"

  # Deep checking requires AWS credentials
  deep_check = false
}

# Terraform Plugin (built-in rules)
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# =============================================================================
# Rule Overrides
# =============================================================================

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Require descriptions for variables
rule "terraform_documented_variables" {
  enabled = true
}

# Require descriptions for outputs
rule "terraform_documented_outputs" {
  enabled = true
}

# Enforce consistent variable types
rule "terraform_typed_variables" {
  enabled = true
}

# Prevent deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Require terraform version constraint
rule "terraform_required_version" {
  enabled = true
}

# Require provider version constraints
rule "terraform_required_providers" {
  enabled = true
}

# Unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Standard module structure
rule "terraform_standard_module_structure" {
  enabled = true
}

# =============================================================================
# AWS-Specific Rules
# =============================================================================

# Ensure IAM policies don't use wildcards
rule "aws_iam_policy_document_too_permissive" {
  enabled = true
}

# Ensure S3 buckets have encryption
rule "aws_s3_bucket_server_side_encryption_configuration" {
  enabled = false  # We handle this explicitly with SSE-S3
}

# Lambda function settings
rule "aws_lambda_function_invalid_runtime" {
  enabled = true
}

# =============================================================================
# Disabled Rules (with justification)
# =============================================================================

# Disabled: We use local modules without version tags
rule "terraform_module_pinned_source" {
  enabled = false
}

# Disabled: Bedrock AgentCore resources don't exist in provider yet
rule "aws_resource_missing_tags" {
  enabled = false
}

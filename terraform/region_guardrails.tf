# Feature-by-region guardrails for AgentCore (Issue #100)

locals {
  # Amazon Bedrock AgentCore General Availability (GA) regions
  # Includes: Runtime, Gateway, Memory, Identity, Observability, Built-in Tools
  # Reference: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html
  agentcore_ga_regions = [
    "us-east-1",      # N. Virginia
    "us-east-2",      # Ohio
    "us-west-2",      # Oregon
    "ap-south-1",     # Mumbai
    "ap-southeast-1", # Singapore
    "ap-southeast-2", # Sydney
    "ap-northeast-1", # Tokyo
    "eu-central-1",   # Frankfurt
    "eu-west-1"       # Ireland
  ]

  # AgentCore Policy Engine Preview regions
  # Reference: https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-bedrock-agentcore-policy-evaluations-preview/
  agentcore_policy_regions = [
    "us-east-1",
    "us-west-2",
    "ap-south-1",
    "ap-southeast-1",
    "ap-southeast-2",
    "ap-northeast-1",
    "eu-central-1",
    "eu-west-1"
  ]

  # AgentCore Evaluations Preview regions
  # Reference: https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-bedrock-agentcore-policy-evaluations-preview/
  agentcore_evaluations_regions = [
    "us-east-1",
    "us-west-2",
    "ap-southeast-2",
    "eu-central-1"
  ]

  # Derived checks for current configuration
  agentcore_is_ga_region         = contains(local.agentcore_ga_regions, local.agentcore_region)
  agentcore_supports_policy      = contains(local.agentcore_policy_regions, local.agentcore_region)
  agentcore_supports_evaluations = contains(local.agentcore_evaluations_regions, local.agentcore_region)
}

resource "terraform_data" "agentcore_region_guardrails" {
  # Use input to ensure this runs and has access to locals/variables
  input = {
    region             = local.agentcore_region
    enable_gateway     = var.enable_gateway
    enable_runtime     = var.enable_runtime
    enable_policy      = var.enable_policy_engine
    enable_evaluations = var.enable_evaluations
  }

  lifecycle {
    # 1. Block core features in non-GA regions
    precondition {
      condition     = !(var.enable_gateway && !local.agentcore_is_ga_region)
      error_message = "AgentCore Gateway is enabled but ${local.agentcore_region} is not a GA region for Amazon Bedrock AgentCore. Please use eu-central-1 (Frankfurt) or eu-west-1 (Ireland)."
    }

    precondition {
      condition     = !(var.enable_runtime && !local.agentcore_is_ga_region)
      error_message = "AgentCore Runtime is enabled but ${local.agentcore_region} is not a GA region for Amazon Bedrock AgentCore. Please use eu-central-1 (Frankfurt) or eu-west-1 (Ireland)."
    }

    # 2. Block Policy Engine in unsupported regions
    precondition {
      condition     = !(var.enable_policy_engine && !local.agentcore_supports_policy)
      error_message = "AgentCore Policy Engine is enabled but is not currently supported in ${local.agentcore_region}. Please use eu-central-1 (Frankfurt) or eu-west-1 (Ireland)."
    }

    # 3. Block Evaluations in unsupported regions
    precondition {
      condition     = !(var.enable_evaluations && !local.agentcore_supports_evaluations)
      error_message = "AgentCore Evaluations is enabled but is not currently supported in ${local.agentcore_region}. Please use eu-central-1 (Frankfurt)."
    }
  }
}

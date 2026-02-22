locals {
  agentcore_region = var.agentcore_region != "" ? var.agentcore_region : var.region
  bedrock_region   = var.bedrock_region != "" ? var.bedrock_region : local.agentcore_region
  bff_region       = var.bff_region != "" ? var.bff_region : local.agentcore_region
  app_id           = var.app_id != "" ? var.app_id : var.agent_name

  # Canonical tag taxonomy (Issue #22, Workstream B).
  # Required keys are always present; user-supplied var.tags supplement non-canonical keys.
  # Merge order: var.tags first, then canonical keys (canonical wins on key conflict).
  canonical_tags = merge(
    var.tags,
    {
      AppID       = local.app_id
      Environment = var.environment
      AgentName   = var.agent_name
      ManagedBy   = "terraform"
      Owner       = var.owner != "" ? var.owner : local.app_id
    }
  )
}

locals {
  agentcore_region = var.agentcore_region != "" ? var.agentcore_region : var.region
  bedrock_region   = var.bedrock_region != "" ? var.bedrock_region : local.agentcore_region
  bff_region       = var.bff_region != "" ? var.bff_region : local.agentcore_region
  app_id           = var.app_id != "" ? var.app_id : var.agent_name
}

# Root module - orchestrates all AgentCore components

module "agentcore_foundation" {
  source = "./modules/agentcore-foundation"

  agent_name  = var.agent_name
  region      = var.region
  environment = var.environment
  tags        = var.tags

  # Gateway configuration
  enable_gateway      = var.enable_gateway
  gateway_name        = var.gateway_name
  mcp_targets         = var.mcp_targets
  gateway_search_type = var.gateway_search_type

  # Identity configuration
  enable_identity   = var.enable_identity
  oauth_return_urls = var.oauth_return_urls

  # Observability
  enable_observability = var.enable_observability
  log_retention_days   = var.log_retention_days
  enable_xray          = var.enable_xray
}

module "agentcore_tools" {
  source = "./modules/agentcore-tools"

  agent_name = var.agent_name
  region     = var.region
  tags       = var.tags

  # Code interpreter
  enable_code_interpreter       = var.enable_code_interpreter
  code_interpreter_network_mode = var.code_interpreter_network_mode
  code_interpreter_vpc_config   = var.code_interpreter_vpc_config

  # Browser
  enable_browser              = var.enable_browser
  browser_network_mode        = var.browser_network_mode
  browser_vpc_config          = var.browser_vpc_config
  enable_browser_recording    = var.enable_browser_recording
  browser_recording_s3_bucket = var.browser_recording_s3_bucket
}

module "agentcore_runtime" {
  source = "./modules/agentcore-runtime"

  agent_name = var.agent_name
  region     = var.region
  tags       = var.tags

  # Runtime configuration
  enable_runtime      = var.enable_runtime
  runtime_source_path = var.runtime_source_path
  runtime_config      = var.runtime_config

  # Memory configuration
  enable_memory = var.enable_memory
  memory_type   = var.memory_type

  # S3 deployment
  deployment_bucket_name = var.deployment_bucket_name
  enable_s3_encryption   = var.enable_s3_encryption

  # Packaging
  enable_packaging = var.enable_packaging
  python_version   = var.python_version

  depends_on = [
    module.agentcore_foundation
  ]
}

module "agentcore_governance" {
  source = "./modules/agentcore-governance"

  agent_name = var.agent_name
  region     = var.region
  tags       = var.tags

  # Policy engine
  enable_policy_engine = var.enable_policy_engine
  cedar_policy_files   = var.cedar_policy_files
  policy_engine_schema = var.policy_engine_schema

  # Evaluations
  enable_evaluations  = var.enable_evaluations
  evaluation_type     = var.evaluation_type
  evaluator_model_id  = var.evaluator_model_id
  evaluation_prompt   = var.evaluation_prompt
  evaluation_criteria = var.evaluation_criteria

  depends_on = [
    module.agentcore_foundation,
    module.agentcore_runtime
  ]
}
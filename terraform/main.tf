# Root module - orchestrates all AgentCore components

module "agentcore_foundation" {
  source = "./modules/agentcore-foundation"

  agent_name     = var.agent_name
  region         = local.agentcore_region
  bedrock_region = local.bedrock_region
  environment    = var.environment
  tags           = var.tags

  # Gateway configuration
  enable_gateway      = var.enable_gateway
  gateway_name        = var.gateway_name
  gateway_role_arn    = var.gateway_role_arn
  mcp_targets         = var.mcp_targets
  gateway_search_type = var.gateway_search_type

  # Identity configuration
  enable_identity   = var.enable_identity
  oauth_return_urls = var.oauth_return_urls

  # Observability
  enable_observability = var.enable_observability
  log_retention_days   = var.log_retention_days
  enable_xray          = var.enable_xray
  alarm_sns_topic_arn  = var.alarm_sns_topic_arn

  # Encryption
  enable_kms  = var.enable_kms
  kms_key_arn = var.kms_key_arn
}

module "agentcore_tools" {
  source = "./modules/agentcore-tools"

  agent_name         = var.agent_name
  region             = local.agentcore_region
  tags               = var.tags
  log_retention_days = var.log_retention_days

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

  # Encryption (deprecated/fallback)
  enable_kms  = var.enable_kms
  kms_key_arn = var.kms_key_arn
}

module "agentcore_runtime" {
  source = "./modules/agentcore-runtime"

  agent_name     = var.agent_name
  region         = local.agentcore_region
  bedrock_region = local.bedrock_region
  tags           = var.tags

  # Runtime configuration
  enable_runtime          = var.enable_runtime
  runtime_source_path     = var.runtime_source_path
  runtime_config          = var.runtime_config
  runtime_role_arn        = var.runtime_role_arn
  runtime_policy_arns     = var.runtime_policy_arns
  runtime_inline_policies = var.runtime_inline_policies

  # Memory configuration
  enable_memory = var.enable_memory
  memory_type   = var.memory_type

  # Inference profile (Bedrock)
  enable_inference_profile           = var.enable_inference_profile
  inference_profile_name             = var.inference_profile_name
  inference_profile_model_source_arn = var.inference_profile_model_source_arn
  inference_profile_description      = var.inference_profile_description
  inference_profile_tags             = var.inference_profile_tags

  # S3 deployment
  deployment_bucket_name = var.deployment_bucket_name
  enable_s3_encryption   = var.enable_s3_encryption
  logging_bucket_id      = module.agentcore_foundation.access_logs_bucket_id

  # Packaging
  enable_packaging    = var.enable_packaging
  python_version      = var.python_version
  lambda_architecture = var.lambda_architecture

  depends_on = [
    module.agentcore_foundation
  ]
}

module "agentcore_governance" {
  source = "./modules/agentcore-governance"

  agent_name     = var.agent_name
  region         = local.agentcore_region
  bedrock_region = local.bedrock_region
  tags           = var.tags

  # Policy engine
  enable_policy_engine   = var.enable_policy_engine
  cedar_policy_files     = var.cedar_policy_files
  policy_engine_schema   = var.policy_engine_schema
  policy_engine_role_arn = var.policy_engine_role_arn

  # Guardrails
  enable_guardrails                   = var.enable_guardrails
  guardrail_name                      = var.guardrail_name
  guardrail_description               = var.guardrail_description
  guardrail_blocked_input_messaging   = var.guardrail_blocked_input_messaging
  guardrail_blocked_outputs_messaging = var.guardrail_blocked_outputs_messaging
  guardrail_filters                   = var.guardrail_filters
  guardrail_sensitive_info_filters    = var.guardrail_sensitive_info_filters

  # Evaluations
  enable_evaluations  = var.enable_evaluations
  evaluation_type     = var.evaluation_type
  evaluator_model_id  = var.evaluator_model_id
  evaluator_role_arn  = var.evaluator_role_arn
  evaluation_prompt   = var.evaluation_prompt
  evaluation_criteria = var.evaluation_criteria

  depends_on = [
    module.agentcore_foundation,
    module.agentcore_runtime
  ]
}

module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff       = var.enable_bff
  agent_name       = var.agent_name
  app_id           = local.app_id
  region           = local.bff_region
  agentcore_region = local.agentcore_region
  environment      = var.environment
  tags             = var.tags

  # Auth Configuration
  oidc_issuer            = var.oidc_issuer
  oidc_client_id         = var.oidc_client_id
  oidc_client_secret_arn = var.oidc_client_secret_arn
  logging_bucket_id      = module.agentcore_foundation.access_logs_bucket_id

  # Integration
  agentcore_runtime_arn = var.bff_agentcore_runtime_arn != "" ? var.bff_agentcore_runtime_arn : module.agentcore_runtime.runtime_arn

  providers = {
    aws = aws.bff
  }

  depends_on = [
    module.agentcore_foundation
  ]
}

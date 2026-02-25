# Root module - orchestrates all AgentCore components

data "aws_caller_identity" "current" {}

module "agentcore_foundation" {
  source = "./modules/agentcore-foundation"

  agent_name     = var.agent_name
  region         = local.agentcore_region
  bedrock_region = local.bedrock_region
  environment    = var.environment
  tags           = local.canonical_tags

  # Gateway configuration
  enable_gateway      = var.enable_gateway
  gateway_name        = var.gateway_name
  gateway_role_arn    = var.gateway_role_arn
  mcp_targets         = var.mcp_targets
  gateway_search_type = var.gateway_search_type

  # Identity configuration
  enable_identity   = var.enable_identity
  oauth_return_urls = var.oauth_return_urls
  oidc_issuer       = var.oidc_issuer

  # Observability
  enable_observability                    = var.enable_observability
  log_retention_days                      = var.log_retention_days
  enable_xray                             = var.enable_xray
  xray_sampling_priority                  = var.xray_sampling_priority
  manage_log_resource_policy              = var.manage_log_resource_policy
  alarm_sns_topic_arn                     = var.alarm_sns_topic_arn
  enable_agent_dashboards                 = var.enable_agent_dashboards
  agent_dashboard_name                    = var.agent_dashboard_name
  dashboard_region                        = var.dashboard_region != "" ? var.dashboard_region : var.region
  dashboard_widgets_override              = var.dashboard_widgets_override
  dashboard_include_runtime_logs          = var.enable_runtime
  dashboard_include_code_interpreter_logs = var.enable_code_interpreter
  dashboard_include_browser_logs          = var.enable_browser
  dashboard_include_evaluator_logs        = var.enable_evaluations
  enable_waf                              = var.enable_waf

  # Encryption
  enable_kms  = var.enable_kms
  kms_key_arn = var.kms_key_arn

  # Inference profile (created here for IAM policy scoping; ARN passed to runtime)
  enable_inference_profile           = var.enable_inference_profile
  inference_profile_name             = var.inference_profile_name
  inference_profile_model_source_arn = var.inference_profile_model_source_arn
  inference_profile_description      = var.inference_profile_description
  inference_profile_tags             = merge(local.canonical_tags, var.inference_profile_tags)
}

module "agentcore_tools" {
  source = "./modules/agentcore-tools"

  agent_name         = var.agent_name
  region             = local.agentcore_region
  tags               = local.canonical_tags
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
  app_id         = local.app_id
  region         = local.agentcore_region
  bedrock_region = local.bedrock_region
  environment    = var.environment
  tags           = local.canonical_tags

  # Runtime configuration
  enable_runtime          = var.enable_runtime
  runtime_source_path     = var.runtime_source_path
  runtime_entry_file      = var.runtime_entry_file
  runtime_config          = var.runtime_config
  runtime_role_arn        = var.runtime_role_arn
  runtime_policy_arns     = var.runtime_policy_arns
  runtime_inline_policies = var.runtime_inline_policies

  # Memory configuration
  enable_memory = var.enable_memory
  memory_type   = var.memory_type

  # Inference profile ARN (profile is created in agentcore_foundation; passed here for SSM persistence)
  inference_profile_arn = module.agentcore_foundation.inference_profile_arn

  # S3 deployment
  deployment_bucket_name = var.deployment_bucket_name
  enable_s3_encryption   = var.enable_s3_encryption
  enable_observability   = var.enable_observability
  logging_bucket_id      = module.agentcore_foundation.access_logs_bucket_id
  proxy_role_arn         = module.agentcore_bff.proxy_role_arn

  # Packaging
  enable_packaging     = var.enable_packaging
  python_version       = var.python_version
  lambda_architecture  = var.lambda_architecture
  reserved_concurrency = var.runtime_reserved_concurrency

  depends_on = [
    module.agentcore_foundation
  ]
}

module "agentcore_governance" {
  source = "./modules/agentcore-governance"

  agent_name     = var.agent_name
  region         = local.agentcore_region
  bedrock_region = local.bedrock_region
  tags           = local.canonical_tags

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

# OIDC Discovery (Build-time Discovery)
data "http" "oidc_config" {
  count = var.enable_bff && var.oidc_issuer != "" ? 1 : 0
  url   = "${trimsuffix(var.oidc_issuer, "/")}/.well-known/openid-configuration"

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  oidc_discovery = try(jsondecode(data.http.oidc_config[0].response_body), {})
}

module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff                       = var.enable_bff
  agent_name                       = var.agent_name
  app_id                           = local.app_id
  region                           = local.bff_region
  agentcore_region                 = local.agentcore_region
  environment                      = var.environment
  tags                             = local.canonical_tags
  log_retention_days               = var.log_retention_days
  enable_audit_log_persistence     = var.enable_bff_audit_log_persistence
  enable_cloudfront_access_logging = var.enable_bff_cloudfront_access_logging
  cloudfront_access_logs_prefix    = var.bff_cloudfront_access_logs_prefix

  # Auth Configuration

  oidc_issuer = var.oidc_issuer

  oidc_authorization_endpoint = var.oidc_authorization_endpoint != "" ? var.oidc_authorization_endpoint : try(local.oidc_discovery.authorization_endpoint, "")

  oidc_token_endpoint = var.oidc_token_endpoint != "" ? var.oidc_token_endpoint : try(local.oidc_discovery.token_endpoint, "")

  oidc_client_id             = var.oidc_client_id
  oidc_client_secret_arn     = var.oidc_client_secret_arn
  custom_domain_name         = var.bff_custom_domain_name
  acm_certificate_arn        = var.bff_acm_certificate_arn
  logging_bucket_id          = module.agentcore_foundation.access_logs_bucket_id
  reserved_concurrency       = var.proxy_reserved_concurrency
  waf_acl_arn                = module.agentcore_foundation.waf_acl_arn
  agentcore_runtime_role_arn = var.bff_agentcore_runtime_role_arn != "" ? var.bff_agentcore_runtime_role_arn : module.agentcore_runtime.runtime_role_arn

  # Integration
  agentcore_runtime_arn  = var.bff_agentcore_runtime_arn != "" ? var.bff_agentcore_runtime_arn : module.agentcore_runtime.runtime_arn
  deployment_bucket_name = module.agentcore_runtime.deployment_bucket_name

  providers = {
    aws = aws.bff
  }

  depends_on = [
    module.agentcore_foundation
  ]
}

resource "aws_api_gateway_rest_api" "bff" {
  # checkov:skip=CKV2_AWS_77: WAF on Rest API requires cost decision
  # checkov:skip=CKV_AWS_237: Intentional harness default; zero-downtime REST API replacement requires parallel cutover design (#79)
  count = var.enable_bff ? 1 : 0

  name        = "agentcore-bff-${var.agent_name}"
  description = "Backend-for-Frontend for ${var.agent_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

resource "aws_api_gateway_deployment" "bff" {
  count = var.enable_bff ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.bff[0].id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.auth,
      aws_api_gateway_resource.api,
      aws_api_gateway_method.login,
      aws_api_gateway_method.callback,
      aws_api_gateway_method.chat
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.login,
    aws_api_gateway_integration.login,
    aws_api_gateway_method.callback,
    aws_api_gateway_integration.callback,
    aws_api_gateway_method.chat,
    aws_api_gateway_integration.chat
  ]
}

resource "aws_api_gateway_stage" "bff" {
  # checkov:skip=CKV_AWS_120: Intentional harness default; API caching is disabled for OIDC callbacks and per-session streaming responses
  # checkov:skip=CKV2_AWS_51: Client Cert not used (Token Handler pattern)
  # checkov:skip=CKV2_AWS_29: WAF managed at CloudFront layer (if enabled)
  # checkov:skip=CKV2_AWS_77: Log4j AMR managed by AWSManagedRulesCommonRuleSet in WAF ACL
  count = var.enable_bff ? 1 : 0

  deployment_id = aws_api_gateway_deployment.bff[0].id
  rest_api_id   = aws_api_gateway_rest_api.bff[0].id
  stage_name    = var.environment

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access[0].arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      tenantId       = "$context.authorizer.tenant_id"
      appId          = "$context.authorizer.app_id"
    })
  }
}

resource "aws_wafv2_web_acl_association" "bff" {
  count        = var.enable_bff && var.waf_acl_arn != "" ? 1 : 0
  resource_arn = aws_api_gateway_stage.bff[0].execution_arn
  web_acl_arn  = var.waf_acl_arn
}

resource "aws_api_gateway_method_settings" "bff" {
  # checkov:skip=CKV_AWS_225: Intentional harness default; method caching is disabled to avoid caching auth/session and streaming traffic
  count = var.enable_bff ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  stage_name  = aws_api_gateway_stage.bff[0].stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"

    # Senior Engineer: Global Throttling
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

# --- Resources ---

resource "aws_api_gateway_resource" "auth" {
  count       = var.enable_bff ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  parent_id   = aws_api_gateway_rest_api.bff[0].root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_resource" "login" {
  count       = var.enable_bff ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  parent_id   = aws_api_gateway_resource.auth[0].id
  path_part   = "login"
}

resource "aws_api_gateway_resource" "callback" {
  count       = var.enable_bff ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  parent_id   = aws_api_gateway_resource.auth[0].id
  path_part   = "callback"
}

resource "aws_api_gateway_resource" "api" {
  count       = var.enable_bff ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  parent_id   = aws_api_gateway_rest_api.bff[0].root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "chat" {
  count       = var.enable_bff ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  parent_id   = aws_api_gateway_resource.api[0].id
  path_part   = "chat"
}

# --- Authorizer ---

resource "aws_api_gateway_authorizer" "token_handler" {
  count           = var.enable_bff ? 1 : 0
  name            = "TokenHandlerAuthorizer"
  rest_api_id     = aws_api_gateway_rest_api.bff[0].id
  authorizer_uri  = aws_lambda_function.authorizer[0].invoke_arn
  identity_source = "method.request.header.Cookie"
  type            = "REQUEST"
}

# --- Methods: GET /auth/login ---

resource "aws_api_gateway_method" "login" {
  # checkov:skip=CKV_AWS_59: Intentional harness default; OIDC login entrypoint must be public and issues only a redirect
  # checkov:skip=CKV2_AWS_53: Validation skipped for redirect-only handler
  count         = var.enable_bff ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.bff[0].id
  resource_id   = aws_api_gateway_resource.login[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "login" {
  count                   = var.enable_bff ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.bff[0].id
  resource_id             = aws_api_gateway_resource.login[0].id
  http_method             = aws_api_gateway_method.login[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth_handler[0].invoke_arn
}

# --- Methods: GET /auth/callback ---

resource "aws_api_gateway_method" "callback" {
  # checkov:skip=CKV_AWS_59: Intentional harness default; OIDC callback must be public and validates state/session in Lambda
  # checkov:skip=CKV2_AWS_53: Validation skipped for OIDC callback
  count         = var.enable_bff ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.bff[0].id
  resource_id   = aws_api_gateway_resource.callback[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "callback" {
  count                   = var.enable_bff ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.bff[0].id
  resource_id             = aws_api_gateway_resource.callback[0].id
  http_method             = aws_api_gateway_method.callback[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth_handler[0].invoke_arn
}

# --- Methods: POST /api/chat ---

resource "aws_api_gateway_method" "chat" {
  # checkov:skip=CKV2_AWS_53: Request body validation handled by Lambda
  count         = var.enable_bff ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.bff[0].id
  resource_id   = aws_api_gateway_resource.chat[0].id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.token_handler[0].id
}

resource "aws_api_gateway_integration" "chat" {
  count                   = var.enable_bff ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.bff[0].id
  resource_id             = aws_api_gateway_resource.chat[0].id
  http_method             = aws_api_gateway_method.chat[0].http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = aws_lambda_function_url.proxy[0].function_url
  connection_type         = "INTERNET"
  credentials             = aws_iam_role.apigw_proxy[0].arn
  response_transfer_mode  = "STREAM"
  timeout_milliseconds    = 900000
}

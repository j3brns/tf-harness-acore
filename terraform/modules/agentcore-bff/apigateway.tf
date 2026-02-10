resource "aws_api_gateway_rest_api" "bff" {
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
  count = var.enable_bff ? 1 : 0

  deployment_id = aws_api_gateway_deployment.bff[0].id
  rest_api_id   = aws_api_gateway_rest_api.bff[0].id
  stage_name    = var.environment

  xray_tracing_enabled = true
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
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.proxy[0].invoke_arn
}
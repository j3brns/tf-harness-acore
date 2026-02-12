resource "aws_api_gateway_rest_api" "bff" {
  # checkov:skip=CKV2_AWS_77: WAF on Rest API requires cost decision
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
  # checkov:skip=CKV2_AWS_51: Client Cert not used (Token Handler pattern)
  # checkov:skip=CKV2_AWS_29: WAF managed at CloudFront layer (if enabled)
  count = var.enable_bff ? 1 : 0

  deployment_id = aws_api_gateway_deployment.bff[0].id
  rest_api_id   = aws_api_gateway_rest_api.bff[0].id
  stage_name    = var.environment

  xray_tracing_enabled = true
}

resource "aws_api_gateway_method_settings" "bff" {
  count = var.enable_bff ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.bff[0].id
  stage_name  = aws_api_gateway_stage.bff[0].stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
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
  timeout_milliseconds    = 29000 # Provider limit, patched to 900000 below
}

# --- Bridge Pattern: Patch for Response Streaming (Rule 1) ---
# This bypasses the 29s provider limit for REST APIs by using the AWS CLI
resource "null_resource" "patch_chat_streaming" {
  count = var.enable_bff ? 1 : 0

  triggers = {
    integration_id = aws_api_gateway_integration.chat[0].id
    # Re-patch if the function URL changes
    uri            = aws_lambda_function_url.proxy[0].function_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Patching chat integration for 15-minute streaming..."
      aws apigateway update-integration \
        --rest-api-id ${aws_api_gateway_rest_api.bff[0].id} \
        --resource-id ${aws_api_gateway_resource.chat[0].id} \
        --http-method ${aws_api_gateway_method.chat[0].http_method} \
        --patch-operations \
          "op='replace',path='/timeoutInMillis',value='900000'" \
          "op='replace',path='/responseTransferMode',value='STREAM'" \
        --region ${var.region}
    EOT
  }

  depends_on = [aws_api_gateway_integration.chat]
}

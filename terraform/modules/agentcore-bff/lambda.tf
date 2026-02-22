# --- Packaging ---
data "archive_file" "auth_handler" {
  count       = var.enable_bff ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/auth_handler.py"
  output_path = "${path.module}/.terraform/auth_handler.zip"
}

data "archive_file" "authorizer" {
  count       = var.enable_bff ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/authorizer.py"
  output_path = "${path.module}/.terraform/authorizer.zip"
}

data "archive_file" "proxy" {
  count       = var.enable_bff ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/proxy.js"
  output_path = "${path.module}/.terraform/proxy.zip"
}

# --- Functions ---

resource "aws_lambda_function" "auth_handler" {

  # checkov:skip=CKV2_AWS_75: CORS managed by API Gateway/CloudFront
  # checkov:skip=CKV_AWS_116: DLQ not required for synchronous OIDC handler
  # checkov:skip=CKV_AWS_117: Public access required for OIDC issuer reachability
  # checkov:skip=CKV_AWS_115: Concurrency managed at account/module level

  count = var.enable_bff ? 1 : 0



  function_name                  = "agentcore-bff-auth-${var.agent_name}"
  role                           = aws_iam_role.auth_handler[0].arn
  handler                        = "auth_handler.lambda_handler"
  runtime                        = "python3.12"
  filename                       = data.archive_file.auth_handler[0].output_path
  source_code_hash               = data.archive_file.auth_handler[0].output_base64sha256
  reserved_concurrent_executions = var.reserved_concurrency > 0 ? var.reserved_concurrency : null

  environment {
    variables = {
      APP_ID                 = var.app_id
      SESSION_TABLE          = aws_dynamodb_table.sessions[0].name
      CLIENT_ID              = var.oidc_client_id
      CLIENT_SECRET_ARN      = var.oidc_client_secret_arn
      ISSUER                 = var.oidc_issuer
      AUTHORIZATION_ENDPOINT = var.oidc_authorization_endpoint
      TOKEN_ENDPOINT         = var.oidc_token_endpoint
      REDIRECT_URI           = "https://${aws_api_gateway_rest_api.bff[0].id}.execute-api.${var.region}.amazonaws.com/${var.environment}/auth/callback"
      SESSION_TTL            = tostring(var.session_ttl_seconds)
    }
  }
}

resource "aws_lambda_function" "authorizer" {

  # checkov:skip=CKV2_AWS_75: Internal authorizer
  # checkov:skip=CKV_AWS_116: DLQ not required for authorizer
  # checkov:skip=CKV_AWS_117: Internal VPC access not required
  # checkov:skip=CKV_AWS_115: Concurrency managed at account/module level

  count = var.enable_bff ? 1 : 0



  function_name                  = "agentcore-bff-authz-${var.agent_name}"
  role                           = aws_iam_role.authorizer[0].arn
  handler                        = "authorizer.lambda_handler"
  runtime                        = "python3.12"
  filename                       = data.archive_file.authorizer[0].output_path
  source_code_hash               = data.archive_file.authorizer[0].output_base64sha256
  reserved_concurrent_executions = var.reserved_concurrency > 0 ? var.reserved_concurrency : null

  environment {
    variables = {
      APP_ID            = var.app_id
      SESSION_TABLE     = aws_dynamodb_table.sessions[0].name
      CLIENT_ID         = var.oidc_client_id
      CLIENT_SECRET_ARN = var.oidc_client_secret_arn
      ISSUER            = var.oidc_issuer
      TOKEN_ENDPOINT    = var.oidc_token_endpoint
    }
  }
}

resource "aws_lambda_function" "proxy" {

  # checkov:skip=CKV2_AWS_75: Protected by Authorizer
  # checkov:skip=CKV_AWS_116: DLQ not required for streaming proxy
  # checkov:skip=CKV_AWS_117: Public access required for Bedrock API reachability

  count = var.enable_bff ? 1 : 0



  function_name                  = "agentcore-bff-proxy-${var.agent_name}"
  role                           = aws_iam_role.proxy[0].arn
  handler                        = "proxy.handler"
  runtime                        = "nodejs20.x"
  filename                       = data.archive_file.proxy[0].output_path
  source_code_hash               = data.archive_file.proxy[0].output_base64sha256
  reserved_concurrent_executions = var.reserved_concurrency > 0 ? var.reserved_concurrency : null

  environment {
    variables = {
      AGENTCORE_RUNTIME_ARN      = var.agentcore_runtime_arn
      AGENTCORE_REGION           = local.agentcore_region
      AGENTCORE_RUNTIME_ROLE_ARN = var.agentcore_runtime_role_arn
      AGENT_NAME                 = var.agent_name
      ENVIRONMENT                = var.environment
      AUDIT_LOGS_ENABLED         = tostring(local.audit_logs_enabled)
      AUDIT_LOGS_BUCKET          = local.audit_logs_enabled ? var.logging_bucket_id : ""
      AUDIT_LOGS_PREFIX          = local.audit_logs_events_prefix
    }
  }
}

resource "aws_lambda_function_url" "proxy" {
  count              = var.enable_bff ? 1 : 0
  function_name      = aws_lambda_function.proxy[0].function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "RESPONSE_STREAM"
}

# --- Permissions ---

resource "aws_lambda_permission" "apigw_auth" {
  count         = var.enable_bff ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_handler[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bff[0].execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_authz" {
  count         = var.enable_bff ? 1 : 0
  statement_id  = "AllowAPIGatewayInvokeAuthz"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bff[0].execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_proxy" {
  count         = var.enable_bff ? 1 : 0
  statement_id  = "AllowAPIGatewayInvokeProxy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.proxy[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.bff[0].execution_arn}/*/*"
}

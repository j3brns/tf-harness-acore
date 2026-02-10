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
  source_file = "${path.module}/src/proxy.py"
  output_path = "${path.module}/.terraform/proxy.zip"
}

# --- Functions ---

resource "aws_lambda_function" "auth_handler" {

  # checkov:skip=CKV2_AWS_75: CORS managed by API Gateway/CloudFront

  count = var.enable_bff ? 1 : 0



  function_name = "agentcore-bff-auth-${var.agent_name}"
  role             = aws_iam_role.auth_handler[0].arn
  handler          = "auth_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.auth_handler[0].output_path
  source_code_hash = data.archive_file.auth_handler[0].output_base64sha256

  environment {
    variables = {
      SESSION_TABLE     = aws_dynamodb_table.sessions[0].name
      CLIENT_ID         = var.oidc_client_id
      CLIENT_SECRET_ARN = var.oidc_client_secret_arn
      ISSUER            = var.oidc_issuer
      REDIRECT_URI      = "https://${aws_api_gateway_rest_api.bff[0].id}.execute-api.${var.region}.amazonaws.com/${var.environment}/auth/callback"
      SESSION_TTL       = tostring(var.session_ttl_seconds)
    }
  }
}

resource "aws_lambda_function" "authorizer" {

  # checkov:skip=CKV2_AWS_75: Internal authorizer

  count = var.enable_bff ? 1 : 0



  function_name = "agentcore-bff-authz-${var.agent_name}"
  role             = aws_iam_role.authorizer[0].arn
  handler          = "authorizer.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.authorizer[0].output_path
  source_code_hash = data.archive_file.authorizer[0].output_base64sha256

  environment {
    variables = {
      SESSION_TABLE = aws_dynamodb_table.sessions[0].name
    }
  }
}

resource "aws_lambda_function" "proxy" {

  # checkov:skip=CKV2_AWS_75: Protected by Authorizer

  count = var.enable_bff ? 1 : 0



  function_name = "agentcore-bff-proxy-${var.agent_name}"
  role             = aws_iam_role.proxy[0].arn
  handler          = "proxy.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.proxy[0].output_path
  source_code_hash = data.archive_file.proxy[0].output_base64sha256

  environment {
    variables = {
      AGENT_ID       = var.agent_gateway_id # Using the variable here
      AGENT_ALIAS_ID = "TSTALIASID"
    }
  }
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
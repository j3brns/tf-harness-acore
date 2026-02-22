# --- Auth Handler Role ---
resource "aws_iam_role" "auth_handler" {
  count = var.enable_bff ? 1 : 0
  name  = "agentcore-bff-auth-${var.agent_name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "auth_handler" {
  count = var.enable_bff ? 1 : 0
  role  = aws_iam_role.auth_handler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.sessions[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.oidc_client_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
      }
    ]
  })
}

# --- Authorizer Role ---
resource "aws_iam_role" "authorizer" {
  count = var.enable_bff ? 1 : 0
  name  = "agentcore-bff-authz-${var.agent_name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "authorizer" {
  count = var.enable_bff ? 1 : 0
  role  = aws_iam_role.authorizer[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.sessions[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.oidc_client_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
      }
    ]
  })
}

# --- Proxy Role ---
resource "aws_iam_role" "proxy" {
  count = var.enable_bff ? 1 : 0
  name  = "agentcore-bff-proxy-${var.agent_name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "proxy" {
  # checkov:skip=CKV_AWS_111: Bedrock actions require wildcard
  # checkov:skip=CKV_AWS_356: STS AssumeRole requires full access to target role
  count = var.enable_bff ? 1 : 0
  role  = aws_iam_role.proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["bedrock-agentcore:InvokeAgentRuntime"]
          Resource = var.agentcore_runtime_arn
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
        }
      ],
      local.audit_logs_enabled ? [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::${var.logging_bucket_id}/${local.audit_logs_events_prefix}*"
        }
      ] : [],
      # Senior Move: Dynamic Session Policies
      var.agentcore_runtime_role_arn != "" ? [
        {
          Effect   = "Allow"
          Action   = ["sts:AssumeRole"]
          Resource = var.agentcore_runtime_role_arn
        }
      ] : []
    )
  })
}

# --- API Gateway Proxy Role ---
resource "aws_iam_role" "apigw_proxy" {
  count = var.enable_bff ? 1 : 0
  name  = "agentcore-bff-apigw-${var.agent_name}-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "apigw_proxy" {
  count = var.enable_bff ? 1 : 0
  role  = aws_iam_role.apigw_proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunctionUrl"]
        Resource = aws_lambda_function.proxy[0].arn
        Condition = {
          StringEquals = {
            "lambda:FunctionUrlAuthType" = "AWS_IAM"
          }
        }
      }
    ]
  })
}

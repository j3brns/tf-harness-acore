locals {
  project_tag                = lookup(var.tags, "Project", "AgentCore")
  bedrock_region             = var.bedrock_region != "" ? var.bedrock_region : var.region
  gateway_target_lambda_arns = sort(distinct([for _, target in var.mcp_targets : target.lambda_arn]))
}

# IAM Role for Bedrock AgentCore Gateway
resource "aws_iam_role" "gateway" {
  count = var.gateway_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      # Rule 7.1: ABAC Scoping
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/Project" = local.project_tag
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Bedrock AgentCore Gateway
resource "aws_iam_role_policy" "gateway" {
  count = var.gateway_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-gateway-policy"
  role  = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "bedrock:InvokeModel",
            "bedrock:InvokeModelWithResponseStream"
          ]
          Resource = local.model_invoke_resource
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/gateway/*"
        }
      ],
      length(local.gateway_target_lambda_arns) > 0 ? [
        {
          Effect = "Allow"
          Action = [
            "lambda:InvokeFunction"
          ]
          Resource = local.gateway_target_lambda_arns
        }
      ] : [],
      var.enable_kms ? [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey"
          ]
          Resource = [var.kms_key_arn]
        }
      ] : []
    )
  })
}

# IAM Role for CloudWatch Logs (Bedrock Service Role)
resource "aws_iam_role" "cloudwatch_logs" {
  count = var.enable_observability ? 1 : 0
  name  = "${var.agent_name}-cw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      # Rule 7.1: ABAC Scoping
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/Project" = local.project_tag
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.enable_observability ? 1 : 0
  name  = "${var.agent_name}-cw-logs-policy"
  role  = aws_iam_role.cloudwatch_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
      }
    ]
  })
}

# Workload Identity (for CI/CD or local execution)
resource "aws_iam_role" "workload_identity" {
  name = "${var.agent_name}-workload-identity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      # Rule 7.1: ABAC Scoping
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/Project" = local.project_tag
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "workload_identity" {
  # checkov:skip=CKV_AWS_107: Fallback path uses wildcard with ABAC condition when inference profile is disabled
  # checkov:skip=CKV_AWS_108: Fallback path uses wildcard with ABAC condition when inference profile is disabled
  # checkov:skip=CKV_AWS_109: Fallback path uses wildcard with ABAC condition when inference profile is disabled
  # checkov:skip=CKV_AWS_110: Fallback path uses wildcard with ABAC condition when inference profile is disabled
  # checkov:skip=CKV_AWS_111: Fallback path uses wildcard with ABAC condition when inference profile is disabled
  # checkov:skip=CKV_AWS_356: Fallback path uses wildcard with ABAC condition when inference profile is disabled
  name = "${var.agent_name}-workload-policy"
  role = aws_iam_role.workload_identity.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      var.enable_inference_profile ? [
        {
          # Preferred path: invocation scoped to the application inference profile ARN.
          # No wildcard resource; profile tags carry cost/quota attribution.
          Sid    = "InvokeViaInferenceProfile"
          Effect = "Allow"
          Action = [
            "bedrock:InvokeModel",
            "bedrock:InvokeModelWithResponseStream",
            "bedrock:GetInferenceProfile"
          ]
          Resource = aws_bedrock_inference_profile.agent[0].inference_profile_arn
        }
        ] : [
        {
          # Fallback path (enable_inference_profile = false): broad ABAC-scoped grant.
          # Rule 14.3 ABAC: StringEqualsIfExists is required because AWS-managed resources
          # (e.g. Bedrock foundation models) cannot carry customer tags — a strict
          # StringEquals would deny model invocation. For user-taggable AgentCore resources
          # (runtimes, gateways, memory) the condition enforces agent-level isolation.
          Sid      = "BedrockABACFallback"
          Effect   = "Allow"
          Action   = ["bedrock:*"]
          Resource = "*"
          Condition = {
            StringEqualsIfExists = {
              "aws:ResourceTag/AgentName" = var.agent_name
            }
          }
        }
      ],
      [
        {
          Effect = "Allow"
          Action = [
            "ssm:GetParameter",
            "ssm:PutParameter",
            "ssm:DeleteParameter"
          ]
          Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/agentcore/${var.agent_name}/*"
        }
      ]
    )
  })
}

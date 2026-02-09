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
          "aws:PrincipalTag/Project" = lookup(var.tags, "Project", "AgentCore")
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
          Resource = "arn:aws:bedrock:${var.region}::foundation-model/*"
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
          "aws:PrincipalTag/Project" = lookup(var.tags, "Project", "AgentCore")
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
          "aws:PrincipalTag/Project" = lookup(var.tags, "Project", "AgentCore")
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "workload_identity" {
  name = "${var.agent_name}-workload-policy"
  role = aws_iam_role.workload_identity.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:*"
        ]
        Resource = "*"
        # Rule 7.2: Resource-level ABAC
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = lookup(var.tags, "Project", "AgentCore")
          }
        }
      },
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
  })
}
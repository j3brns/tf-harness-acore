# IAM Role for Gateway
resource "aws_iam_role" "gateway" {
  count = var.enable_gateway ? 1 : 0
  name  = "${var.agent_name}-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
      # Rule 7.1: ABAC Scoping - Prevent lateral movement
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/Project" = var.tags["Project"]
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Gateway to invoke Lambda targets
resource "aws_iam_role_policy" "gateway" {
  count = var.enable_gateway ? 1 : 0
  name  = "${var.agent_name}-gateway-policy"
  role  = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          for target in var.mcp_targets : target.lambda_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDeliveryService",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "arn:aws:xray:${var.region}:${data.aws_caller_identity.current.account_id}:*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# IAM Role for Workload Identity
resource "aws_iam_role" "workload_identity" {
  count = var.enable_identity ? 1 : 0
  name  = "${var.agent_name}-workload-identity-role"

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
          "aws:PrincipalTag/Project" = var.tags["Project"]
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Workload Identity
resource "aws_iam_role_policy" "workload_identity" {
  count = var.enable_identity ? 1 : 0
  name  = "${var.agent_name}-workload-identity-policy"
  role  = aws_iam_role.workload_identity[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        # AWS-REQUIRED: sts:GetCallerIdentity does not support resource-level scoping
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/agentcore-*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# IAM Role for CloudWatch Log Delivery
resource "aws_iam_role" "cloudwatch_logs" {
  count = var.enable_observability ? 1 : 0
  name  = "${var.agent_name}-cloudwatch-logs-role"

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
          "aws:PrincipalTag/Project" = var.tags["Project"]
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.enable_observability ? 1 : 0
  name  = "${var.agent_name}-cloudwatch-logs-policy"
  role  = aws_iam_role.cloudwatch_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
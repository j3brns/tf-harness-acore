locals {
  project_tag = lookup(var.tags, "Project", "AgentCore")
}

# IAM Role for Agent Runtime
resource "aws_iam_role" "runtime" {
  count = var.enable_runtime && var.runtime_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-runtime-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
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
      }],
      # Senior Move: Allow Proxy to assume this role with session policies
      var.proxy_role_arn != "" ? [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = var.proxy_role_arn
          }
        }
      }] : []
    )
  })

  tags = var.tags
}

# Base policy for runtime role
resource "aws_iam_role_policy" "runtime_base" {
  count = var.enable_runtime && var.runtime_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-runtime-base-policy"
  role  = aws_iam_role.runtime[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/runtime/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${local.deployment_bucket}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = "arn:aws:s3:::${local.deployment_bucket}"
      }
    ]
  })
}

# Attach additional policies
resource "aws_iam_role_policy_attachment" "runtime_additional" {
  count      = var.enable_runtime && var.runtime_role_arn == "" ? length(var.runtime_policy_arns) : 0
  role       = aws_iam_role.runtime[0].name
  policy_arn = var.runtime_policy_arns[count.index]
}

# Attach inline policies
resource "aws_iam_role_policy" "runtime_inline" {
  for_each = var.enable_runtime && var.runtime_role_arn == "" ? var.runtime_inline_policies : {}

  name   = each.key
  role   = aws_iam_role.runtime[0].id
  policy = each.value
}

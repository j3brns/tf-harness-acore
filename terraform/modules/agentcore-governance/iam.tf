locals {
  project_tag = lookup(var.tags, "Project", "AgentCore")
}

# IAM Role for Policy Engine
resource "aws_iam_role" "policy_engine" {
  count = var.enable_policy_engine && var.policy_engine_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-policy-engine-role"

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
          "aws:PrincipalTag/Project" = local.project_tag
        }
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Policy Engine
resource "aws_iam_role_policy" "policy_engine" {
  count = var.enable_policy_engine && var.policy_engine_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-policy-engine-policy"
  role  = aws_iam_role.policy_engine[0].id

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
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/policy-engine/*"
      }
    ]
  })
}

# IAM Role for Evaluator
resource "aws_iam_role" "evaluator" {
  count = var.enable_evaluations && var.evaluator_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-evaluator-role"

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

# IAM Policy for Evaluator
resource "aws_iam_role_policy" "evaluator" {
  count = var.enable_evaluations && var.evaluator_role_arn == "" ? 1 : 0
  name  = "${var.agent_name}-evaluator-policy"
  role  = aws_iam_role.evaluator[0].id

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
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/evaluator/*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/${var.evaluator_model_id}"
      }
    ]
  })
}

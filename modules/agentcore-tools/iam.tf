# IAM Role for Code Interpreter
resource "aws_iam_role" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0
  name  = "${var.agent_name}-code-interpreter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Code Interpreter
resource "aws_iam_role_policy" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0
  name  = "${var.agent_name}-code-interpreter-policy"
  role  = aws_iam_role.code_interpreter[0].id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/code-interpreter/*"
      },
      # VPC access if needed
      var.code_interpreter_network_mode == "VPC" ? {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      } : null,
      # KMS encryption
      var.enable_kms ? {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn != "" ? [var.kms_key_arn] : ["*"]
      } : null
    ]
  })
}

# IAM Role for Browser
resource "aws_iam_role" "browser" {
  count = var.enable_browser ? 1 : 0
  name  = "${var.agent_name}-browser-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock-agentcore.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# IAM Policy for Browser
resource "aws_iam_role_policy" "browser" {
  count = var.enable_browser ? 1 : 0
  name  = "${var.agent_name}-browser-policy"
  role  = aws_iam_role.browser[0].id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/browser/*"
      },
      # S3 access for recording
      var.enable_browser_recording && var.browser_recording_s3_bucket != "" ? {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${var.browser_recording_s3_bucket}/${var.browser_recording_s3_prefix}*"
      } : null,
      # VPC access if needed
      var.browser_network_mode == "VPC" ? {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      } : null,
      # KMS encryption
      var.enable_kms ? {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn != "" ? [var.kms_key_arn] : ["*"]
      } : null
    ]
  })
}

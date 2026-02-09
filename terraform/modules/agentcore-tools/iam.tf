locals {
  project_tag = lookup(var.tags, "Project", "AgentCore")

  code_interpreter_subnet_arns = var.code_interpreter_vpc_config != null ? [
    for subnet_id in var.code_interpreter_vpc_config.subnet_ids :
    "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:subnet/${subnet_id}"
  ] : []
  code_interpreter_security_group_arns = var.code_interpreter_vpc_config != null ? [
    for sg_id in var.code_interpreter_vpc_config.security_group_ids :
    "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/${sg_id}"
  ] : []
  browser_subnet_arns = var.browser_vpc_config != null ? [
    for subnet_id in var.browser_vpc_config.subnet_ids :
    "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:subnet/${subnet_id}"
  ] : []
  browser_security_group_arns = var.browser_vpc_config != null ? [
    for sg_id in var.browser_vpc_config.security_group_ids :
    "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:security-group/${sg_id}"
  ] : []
}

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

# IAM Policy for Code Interpreter
resource "aws_iam_role_policy" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0
  name  = "${var.agent_name}-code-interpreter-policy"
  role  = aws_iam_role.code_interpreter[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/code-interpreter/*"
        }
      ],
      # AWS-REQUIRED: EC2 network interface APIs do not support resource-level scoping.
      var.code_interpreter_network_mode == "VPC" ? [
        {
          Effect = "Allow"
          Action = [
            "ec2:CreateNetworkInterface",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface",
            "ec2:AssignPrivateIpAddresses",
            "ec2:UnassignPrivateIpAddresses"
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "ec2:Subnet"        = local.code_interpreter_subnet_arns
              "ec2:SecurityGroup" = local.code_interpreter_security_group_arns
            }
          }
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

# IAM Policy for Browser
resource "aws_iam_role_policy" "browser" {
  count = var.enable_browser ? 1 : 0
  name  = "${var.agent_name}-browser-policy"
  role  = aws_iam_role.browser[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/browser/*"
        }
      ],
      var.enable_browser_recording && var.browser_recording_s3_bucket != "" ? [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:PutObjectAcl"
          ]
          Resource = "arn:aws:s3:::${var.browser_recording_s3_bucket}/${var.browser_recording_s3_prefix}*"
        }
      ] : [],
      # AWS-REQUIRED: EC2 network interface APIs do not support resource-level scoping.
      var.browser_network_mode == "VPC" ? [
        {
          Effect = "Allow"
          Action = [
            "ec2:CreateNetworkInterface",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface",
            "ec2:AssignPrivateIpAddresses",
            "ec2:UnassignPrivateIpAddresses"
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "ec2:Subnet"        = local.browser_subnet_arns
              "ec2:SecurityGroup" = local.browser_security_group_arns
            }
          }
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
# Browser tool for web navigation
resource "aws_bedrockagentcore_browser" "web" {
  count = var.enable_browser ? 1 : 0

  name               = "${var.agent_name}-browser"
  execution_role_arn = aws_iam_role.browser[0].arn

  # Network configuration
  network_configuration {
    network_mode = var.browser_network_mode

    dynamic "vpc_config" {
      for_each = var.browser_network_mode == "VPC" && var.browser_vpc_config != null ? [var.browser_vpc_config] : []
      content {
        security_groups             = vpc_config.value.security_group_ids
        subnets                     = vpc_config.value.subnet_ids
        associate_public_ip_address = vpc_config.value.associate_public_ip
      }
    }
  }

  # Session recording configuration
  dynamic "recording_configuration" {
    for_each = var.enable_browser_recording && var.browser_recording_s3_bucket != "" ? [1] : []
    content {
      enabled = true

      s3_configuration {
        bucket_name = var.browser_recording_s3_bucket
        prefix      = var.browser_recording_s3_prefix
      }
    }
  }

  tags = var.tags
}

# CloudWatch Log Group for Browser
resource "aws_cloudwatch_log_group" "browser" {
  count = var.enable_browser ? 1 : 0

  name              = "/aws/bedrock/agentcore/browser/${var.agent_name}"
  retention_in_days = 30

  tags = var.tags
}

# S3 bucket policy for browser recording (if provided)
data "aws_s3_bucket" "browser_recording" {
  count  = var.enable_browser && var.enable_browser_recording && var.browser_recording_s3_bucket != "" ? 1 : 0
  bucket = var.browser_recording_s3_bucket
}

resource "aws_s3_bucket_policy" "browser_recording" {
  count  = var.enable_browser && var.enable_browser_recording && var.browser_recording_s3_bucket != "" ? 1 : 0
  bucket = data.aws_s3_bucket.browser_recording[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBedrockAgentCoreWrite"
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${var.browser_recording_s3_bucket}/${var.browser_recording_s3_prefix}*"
      }
    ]
  })
}

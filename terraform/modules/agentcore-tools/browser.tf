# Browser - Native Provider Resource (v6.33.0)
resource "aws_bedrockagentcore_browser" "this" {
  count = var.enable_browser ? 1 : 0

  name               = "${var.agent_name}-browser"
  execution_role_arn = aws_iam_role.browser[0].arn

  network_configuration {
    execution_mode = var.browser_network_mode
    dynamic "vpc_configuration" {
      for_each = var.browser_vpc_config != null ? [var.browser_vpc_config] : []
      content {
        subnet_ids          = vpc_configuration.value.subnet_ids
        security_group_ids  = vpc_configuration.value.security_group_ids
        associate_public_ip = vpc_configuration.value.associate_public_ip
      }
    }
  }

  dynamic "recording" {
    for_each = var.enable_browser_recording && var.browser_recording_s3_bucket != "" ? [1] : []
    content {
      s3_bucket_name = var.browser_recording_s3_bucket
      s3_key_prefix  = var.browser_recording_s3_prefix
    }
  }

  tags = var.tags

  depends_on = [aws_iam_role.browser]
}

# CloudWatch Log Group for Browser
resource "aws_cloudwatch_log_group" "browser" {
  count = var.enable_browser ? 1 : 0

  name              = "/aws/bedrock/agentcore/browser/${var.agent_name}"
  retention_in_days = var.log_retention_days

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
        # AWS-REQUIRED: Policy requires specific resource scoping for security
        Resource = "arn:aws:s3:::${var.browser_recording_s3_bucket}/${var.browser_recording_s3_prefix}*"
      }
    ]
  })
}

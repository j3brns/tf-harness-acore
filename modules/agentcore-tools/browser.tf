# Browser - CLI-based provisioning
resource "null_resource" "browser" {
  count = var.enable_browser ? 1 : 0

  triggers = {
    name               = "${var.agent_name}-browser"
    execution_role_arn = aws_iam_role.browser[0].arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-browser \
        --name "${self.triggers.name}" \
        --role-arn "${self.triggers.execution_role_arn}" \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/browser_output.json

      if [ ! -s "${path.module}/.terraform/browser_output.json" ]; then
        exit 1
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [aws_iam_role.browser]
}

data "external" "browser_output" {
  count = var.enable_browser ? 1 : 0
  program = ["cat", "${path.module}/.terraform/browser_output.json"]
  depends_on = [null_resource.browser]
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

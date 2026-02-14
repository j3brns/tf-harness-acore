# Browser - CLI-based provisioning with SSM Persistence (Rule 5)
resource "null_resource" "browser" {
  count = var.enable_browser ? 1 : 0

  triggers = {
    agent_name         = var.agent_name
    region             = var.region
    name               = "${var.agent_name}-browser"
    execution_role_arn = aws_iam_role.browser[0].arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-browser \
        --name "${self.triggers.name}" \
        --role-arn "${self.triggers.execution_role_arn}" \
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/browser_output.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/browser_output.json" ]; then
        echo "ERROR: Failed to create browser"
        exit 1
      fi

      BROWSER_ID=$(jq -r '.browserId' < "${path.module}/.terraform/browser_output.json")
      BROWSER_ARN=$(jq -r '.browserArn' < "${path.module}/.terraform/browser_output.json")

      # Rule 5.1: SSM Persistence
      echo "Persisting Browser metadata to SSM..."
      aws ssm put-parameter --name "/agentcore/${self.triggers.agent_name}/browser/id" --value "$BROWSER_ID" --type "String" --overwrite --region ${self.triggers.region}
      aws ssm put-parameter --name "/agentcore/${self.triggers.agent_name}/browser/arn" --value "$BROWSER_ARN" --type "String" --overwrite --region ${self.triggers.region}
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Cleanup Hooks
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      BROWSER_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/browser/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)

      if [ -n "$BROWSER_ID" ]; then
        echo "Deleting Browser $BROWSER_ID..."
        aws bedrock-agentcore-control delete-browser --browser-identifier "$BROWSER_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/browser/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [aws_iam_role.browser]
}

data "aws_ssm_parameter" "browser_id" {
  count = var.enable_browser ? 1 : 0
  name  = "/agentcore/${var.agent_name}/browser/id"

  depends_on = [null_resource.browser]
}

data "aws_ssm_parameter" "browser_arn" {
  count = var.enable_browser ? 1 : 0
  name  = "/agentcore/${var.agent_name}/browser/arn"

  depends_on = [null_resource.browser]
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

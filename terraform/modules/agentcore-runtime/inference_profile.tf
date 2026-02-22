# Inference profile ARN persistence
#
# The application inference profile is created in agentcore-foundation (native Terraform).
# This module receives the ARN as an input and persists it to SSM Parameter Store so that
# agent code running in the runtime can discover it without hardcoding or re-querying Terraform.
resource "aws_ssm_parameter" "inference_profile_arn" {
  # checkov:skip=CKV_AWS_337: Stores a non-secret Bedrock inference profile ARN; String parameter is intentional (no secret material).
  count = var.inference_profile_arn != "" && var.inference_profile_arn != null ? 1 : 0

  name  = "/agentcore/${var.agent_name}/inference-profile/arn"
  type  = "String"
  value = var.inference_profile_arn

  tags = var.tags
}

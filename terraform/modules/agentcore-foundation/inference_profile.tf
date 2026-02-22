# Bedrock application inference profile
#
# When enabled, all model invocations are routed through this profile instead of
# directly referencing foundation-model ARNs. This allows:
#   - IAM policies to be scoped to a specific, customer-owned ARN (no wildcard)
#   - Per-agent cost allocation via profile tags
#   - Quota management at the application boundary
resource "aws_bedrock_inference_profile" "agent" {
  count       = var.enable_inference_profile ? 1 : 0
  name        = var.inference_profile_name
  description = var.inference_profile_description

  model_source {
    copy_from = var.inference_profile_model_source_arn
  }

  tags = merge(var.tags, var.inference_profile_tags)
}

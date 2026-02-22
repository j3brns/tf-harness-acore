# Native gateway outputs
locals {
  gateway_id = var.enable_gateway && length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_id : null

  gateway_arn = var.enable_gateway && length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_arn : null

  gateway_endpoint = var.enable_gateway && length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_url : null

  # IAM resource for Bedrock invocation actions.
  # When an application inference profile exists, scope to its ARN — eliminates
  # the foundation-model/* wildcard and enables per-agent quota/cost tracking.
  # Falls back to the regional foundation-model/* wildcard when no profile is configured.
  model_invoke_resource = var.enable_inference_profile ? aws_bedrock_inference_profile.agent[0].arn : "arn:aws:bedrock:${local.bedrock_region}::foundation-model/*"
}

# Native gateway outputs
locals {
  gateway_id = var.enable_gateway && length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_id : null

  gateway_arn = var.enable_gateway && length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_arn : null

  gateway_endpoint = var.enable_gateway && length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_url : null
}

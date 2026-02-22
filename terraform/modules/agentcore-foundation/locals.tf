# Unified outputs for Gateway (CLI vs Native)
locals {
  use_native = var.use_native_gateway && var.enable_gateway

  gateway_id = local.use_native ? (
    length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_id : null
    ) : (
    var.enable_gateway && length(data.aws_ssm_parameter.gateway_id) > 0 ? data.aws_ssm_parameter.gateway_id[0].value : null
  )

  gateway_arn = local.use_native ? (
    length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_arn : null
    ) : (
    var.enable_gateway && length(data.aws_ssm_parameter.gateway_arn) > 0 ? data.aws_ssm_parameter.gateway_arn[0].value : null
  )

  gateway_endpoint = local.use_native ? (
    length(aws_bedrockagentcore_gateway.this) > 0 ? aws_bedrockagentcore_gateway.this[0].gateway_url : null
    ) : (
    var.enable_gateway && length(data.aws_ssm_parameter.gateway_endpoint) > 0 ? data.aws_ssm_parameter.gateway_endpoint[0].value : null
  )
}

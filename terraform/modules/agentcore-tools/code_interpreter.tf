# Code Interpreter - Native Provider Resource (v6.33.0)
resource "aws_bedrockagentcore_code_interpreter" "this" {
  count = var.enable_code_interpreter ? 1 : 0

  name               = "${var.agent_name}-code-interpreter"
  execution_role_arn = aws_iam_role.code_interpreter[0].arn

  network_configuration {
    execution_mode = var.code_interpreter_network_mode
    dynamic "vpc_configuration" {
      for_each = var.code_interpreter_vpc_config != null ? [var.code_interpreter_vpc_config] : []
      content {
        subnet_ids          = vpc_configuration.value.subnet_ids
        security_group_ids  = vpc_configuration.value.security_group_ids
        associate_public_ip = vpc_configuration.value.associate_public_ip
      }
    }
  }

  tags = var.tags

  depends_on = [aws_iam_role.code_interpreter]
}

# CloudWatch Log Group for Code Interpreter
resource "aws_cloudwatch_log_group" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  name              = "/aws/bedrock/agentcore/code-interpreter/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

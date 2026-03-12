# Code Interpreter - Native Provider Resource (v6.33.0)
resource "aws_bedrockagentcore_code_interpreter" "this" {
  count = var.enable_code_interpreter ? 1 : 0

  name               = "${var.agent_name}-code-interpreter"
  execution_role_arn = aws_iam_role.code_interpreter[0].arn

  network_configuration {
    network_mode = var.code_interpreter_network_mode
    dynamic "vpc_config" {
      for_each = var.code_interpreter_vpc_config != null ? [var.code_interpreter_vpc_config] : []
      content {
        subnets         = vpc_config.value.subnet_ids
        security_groups = vpc_config.value.security_group_ids
      }
    }
  }

  depends_on = [aws_iam_role.code_interpreter]
}

# CloudWatch Log Group for Code Interpreter
resource "aws_cloudwatch_log_group" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  name              = "/aws/bedrock/agentcore/code-interpreter/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

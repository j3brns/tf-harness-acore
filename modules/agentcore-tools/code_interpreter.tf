# Code Interpreter for Python execution
resource "aws_bedrockagentcore_code_interpreter" "python" {
  count = var.enable_code_interpreter ? 1 : 0

  name               = "${var.agent_name}-code-interpreter"
  execution_role_arn = aws_iam_role.code_interpreter[0].arn

  # Network configuration
  network_configuration {
    network_mode = var.code_interpreter_network_mode

    dynamic "vpc_config" {
      for_each = var.code_interpreter_network_mode == "VPC" && var.code_interpreter_vpc_config != null ? [var.code_interpreter_vpc_config] : []
      content {
        security_groups             = vpc_config.value.security_group_ids
        subnets                     = vpc_config.value.subnet_ids
        associate_public_ip_address = vpc_config.value.associate_public_ip
      }
    }
  }

  # Execution timeout
  execution_timeout_seconds = var.code_interpreter_execution_timeout

  tags = var.tags
}

# CloudWatch Log Group for Code Interpreter
resource "aws_cloudwatch_log_group" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  name              = "/aws/bedrock/agentcore/code-interpreter/${var.agent_name}"
  retention_in_days = 30

  tags = var.tags
}

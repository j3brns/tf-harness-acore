# Code Interpreter - CLI-based provisioning
resource "null_resource" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  triggers = {
    name               = "${var.agent_name}-code-interpreter"
    execution_role_arn = aws_iam_role.code_interpreter[0].arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-code-interpreter \
        --name "${self.triggers.name}" \
        --role-arn "${self.triggers.execution_role_arn}" \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/interpreter_output.json

      if [ ! -s "${path.module}/.terraform/interpreter_output.json" ]; then
        exit 1
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [aws_iam_role.code_interpreter]
}

data "external" "interpreter_output" {
  count = var.enable_code_interpreter ? 1 : 0
  program = ["cat", "${path.module}/.terraform/interpreter_output.json"]
  depends_on = [null_resource.code_interpreter]
}

# CloudWatch Log Group for Code Interpreter
resource "aws_cloudwatch_log_group" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  name              = "/aws/bedrock/agentcore/code-interpreter/${var.agent_name}"
  retention_in_days = 30

  tags = var.tags
}

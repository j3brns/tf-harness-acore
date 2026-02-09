# Code Interpreter - CLI-based provisioning with SSM Persistence (Rule 5)
resource "null_resource" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  triggers = {
    agent_name         = var.agent_name
    region             = var.region
    name               = "${var.agent_name}-code-interpreter"
    execution_role_arn = aws_iam_role.code_interpreter[0].arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-code-interpreter \
        --name "${self.triggers.name}" \
        --role-arn "${self.triggers.execution_role_arn}" \
        --region ${self.triggers.region} \
        --output json > "${path.module}/.terraform/interpreter_output.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/interpreter_output.json" ]; then
        echo "ERROR: Failed to create code interpreter"
        exit 1
      fi
      
      INTERPRETER_ID=$(jq -r '.interpreterId' < "${path.module}/.terraform/interpreter_output.json")
      
      # Rule 5.1: SSM Persistence
      echo "Persisting Interpreter ID to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${self.triggers.agent_name}/interpreter/id" \
        --value "$INTERPRETER_ID" \
        --type "String" \
        --overwrite \
        --region ${self.triggers.region}
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Cleanup Hooks
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      INTERPRETER_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/interpreter/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)
      
      if [ -n "$INTERPRETER_ID" ]; then
        echo "Deleting Code Interpreter $INTERPRETER_ID..."
        aws bedrock-agentcore-control delete-code-interpreter --interpreter-identifier "$INTERPRETER_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/interpreter/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [aws_iam_role.code_interpreter]
}

data "external" "interpreter_output" {
  count      = var.enable_code_interpreter ? 1 : 0
  program    = ["cat", "${path.module}/.terraform/interpreter_output.json"]
  depends_on = [null_resource.code_interpreter]
}

# CloudWatch Log Group for Code Interpreter
resource "aws_cloudwatch_log_group" "code_interpreter" {
  count = var.enable_code_interpreter ? 1 : 0

  name              = "/aws/bedrock/agentcore/code-interpreter/${var.agent_name}"
  retention_in_days = 30

  tags = var.tags
}

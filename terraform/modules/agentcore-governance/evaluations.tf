# Custom Evaluator for Agent Quality Assessment
# Note: Native aws_bedrockagentcore_evaluator resource not yet available in Terraform

resource "null_resource" "custom_evaluator" {
  count = var.enable_evaluations ? 1 : 0

  triggers = {
    agent_name      = var.agent_name
    region          = var.region
    model_id        = var.evaluator_model_id
    evaluation_type = var.evaluation_type
    prompt_hash     = sha256(var.evaluation_prompt)
    criteria_hash   = sha256(jsonencode(var.evaluation_criteria))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Creating custom evaluator for ${var.agent_name}..."

      # Prepare evaluation criteria
      CRITERIA='${jsonencode(var.evaluation_criteria)}'

      # Create evaluator
      aws bedrock-agentcore-control create-evaluator \
        --name "${var.agent_name}-evaluator" \
        --agent-name "${var.agent_name}" \
        --evaluation-level ${var.evaluation_type} \
        --evaluation-role-arn "${var.evaluator_role_arn != "" ? var.evaluator_role_arn : aws_iam_role.evaluator[0].arn}" \
        --model-id "${var.evaluator_model_id}" \
        --prompt "${var.evaluation_prompt}" \
        %{if length(var.evaluation_criteria) > 0}
        --criteria "$CRITERIA" \
        %{endif}
        --region ${var.region} \
        --output json > "${path.module}/.terraform/evaluator.json"

      # Rule 1.2: Fail Fast
      if [ ! -s "${path.module}/.terraform/evaluator.json" ]; then
        echo "ERROR: Failed to create custom evaluator"
        exit 1
      fi

      # Extract evaluator ID
      EVALUATOR_ID=$(jq -r '.evaluatorId // empty' < "${path.module}/.terraform/evaluator.json")
      
      if [ -z "$EVALUATOR_ID" ]; then
        echo "ERROR: Evaluator ID missing from output"
        exit 1
      fi

      # Rule 5.1: SSM Persistence
      echo "Persisting Evaluator ID to SSM..."
      aws ssm put-parameter \
        --name "/agentcore/${var.agent_name}/evaluator/id" \
        --value "$EVALUATOR_ID" \
        --type "String" \
        --overwrite \
        --region ${var.region}

      echo "$EVALUATOR_ID" > "${path.module}/.terraform/evaluator_id.txt"
      echo "Custom evaluator created successfully"
    EOT

    interpreter = ["bash", "-c"]
  }

  # Rule 6.1: Cleanup Hooks
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set +e
      EVALUATOR_ID=$(aws ssm get-parameter --name "/agentcore/${self.triggers.agent_name}/evaluator/id" --query "Parameter.Value" --output text --region ${self.triggers.region} 2>/dev/null)
      
      if [ -n "$EVALUATOR_ID" ]; then
        echo "Deleting Evaluator $EVALUATOR_ID..."
        aws bedrock-agentcore-control delete-evaluator --evaluator-identifier "$EVALUATOR_ID" --region ${self.triggers.region}
        aws ssm delete-parameter --name "/agentcore/${self.triggers.agent_name}/evaluator/id" --region ${self.triggers.region}
      fi
    EOT

    interpreter = ["bash", "-c"]
  }

  depends_on = [
    aws_iam_role.evaluator
  ]
}

# CloudWatch log group for evaluator
resource "aws_cloudwatch_log_group" "evaluator" {
  count = var.enable_evaluations ? 1 : 0

  name              = "/aws/bedrock/agentcore/evaluator/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# CloudWatch Metric Alarm for evaluation errors
resource "aws_cloudwatch_metric_alarm" "evaluation_errors" {
  count = var.enable_evaluations && var.enable_evaluation_monitoring ? 1 : 0

  alarm_name          = "${var.agent_name}-evaluation-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "EvaluationErrors"
  namespace           = "AWS/BedrockAgentCore"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when evaluation errors exceed threshold"
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# CloudWatch Metric Alarm for evaluation latency
resource "aws_cloudwatch_metric_alarm" "evaluation_latency" {
  count = var.enable_evaluations && var.enable_evaluation_monitoring ? 1 : 0

  alarm_name          = "${var.agent_name}-evaluation-latency"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "EvaluationLatency"
  namespace           = "AWS/BedrockAgentCore"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000" # 5 seconds in milliseconds
  alarm_description   = "Alert when evaluation latency is high"
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Data source to read evaluator output
data "external" "evaluator_output" {
  count = var.enable_evaluations ? 1 : 0

  program = ["cat", "${path.module}/.terraform/evaluator.json"]

  depends_on = [null_resource.custom_evaluator]
}
# Agent Runtime - Native Provider Resource (v6.33.0)
resource "aws_bedrockagentcore_agent_runtime" "this" {
  count = var.enable_runtime ? 1 : 0

  agent_runtime_name = "${var.agent_name}-runtime"
  role_arn           = var.runtime_role_arn != "" ? var.runtime_role_arn : aws_iam_role.runtime[0].arn

  agent_runtime_artifact {
    code_configuration {
      runtime     = var.python_version
      entry_point = [var.runtime_entry_file]
      code {
        s3 {
          bucket = local.deployment_bucket
          prefix = local.deployment_key
        }
      }
    }
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  tags = var.tags

  depends_on = [
    null_resource.package_code
  ]
}

# Agent Memory - Native Provider Resource (v6.33.0)
resource "aws_bedrockagentcore_memory" "short_term" {
  count = var.enable_memory && (var.memory_type == "SHORT_TERM" || var.memory_type == "BOTH") ? 1 : 0

  name                  = "${var.agent_name}-short-term"
  event_expiry_duration = 7 # Min 7 days for native resource

  tags = var.tags
}

resource "aws_bedrockagentcore_memory" "long_term" {
  count = var.enable_memory && (var.memory_type == "LONG_TERM" || var.memory_type == "BOTH") ? 1 : 0

  name                  = "${var.agent_name}-long-term"
  event_expiry_duration = 365

  tags = var.tags
}

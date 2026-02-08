# ADR 0002: CLI-Based Resources via null_resource

## Status

Accepted

## Context

The AWS Bedrock AgentCore suite is currently not supported by the `hashicorp/aws` Terraform provider. While some resources (Gateway, Identity) appeared to have native types in some documentation, local validation confirmed that they do not yet exist in the provider registry (up to v5.100.0).

Resources requiring CLI-based provisioning:
- Gateway (MCP)
- Workload Identity
- Browser
- Code Interpreter
- Agent Runtime
- Memory (short-term and long-term)
- Policy Engine
- Cedar Policies
- Evaluators
- OAuth2 Credential Providers

Validation with the local Terraform provider and `terraform-mcp-server` confirmed these gaps.

## Decision

Use `null_resource` with `local-exec` provisioner + AWS CLI for missing resources.

Pattern: AWS CLI -> JSON output -> `data.external` -> Terraform outputs

## Implementation Pattern

```hcl
resource "null_resource" "resource_name" {
  triggers = {
    config_hash = sha256(jsonencode(var.resource_config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      aws bedrock-agentcore-control create-X \
        --name ${var.resource_name} \
        --region ${var.region} \
        --output json > ${path.module}/.terraform/output.json

      # Verify success
      if [ ! -f "${path.module}/.terraform/output.json" ]; then
        echo "ERROR: Command failed"
        exit 1
      fi
    EOT
  }
}

data "external" "resource_output" {
  program = ["cat", "${path.module}/.terraform/output.json"]
  depends_on = [null_resource.resource_name]
}

output "resource_id" {
  value = data.external.resource_output.result.resourceId
}
```

## Rationale

- Allows immediate implementation without waiting for AWS provider updates
- Maintains infrastructure-as-code principles
- State management via file outputs + external data sources
- Clear migration path when native resources become available
- Idempotent with hash-based triggers

## Consequences

### Positive
- Can deploy full feature set immediately
- Documented patterns for future migration
- Idempotent with hash-based triggers
- JSON outputs provide structured data

### Negative
- Requires AWS CLI availability on execution machine
- State stored in local files (less reliable than native resources)
- More complex than native Terraform resources
- No automatic drift detection

## Migration Path

When AWS provider adds native resources:

1. Run `terraform import aws_bedrockagentcore_X.main <id>` for CLI-created resources
2. Replace `null_resource` with native resource definition
3. Update outputs to use native attributes
4. Run `terraform plan` (should show no changes)
5. Remove data.external sources
6. Clean up `.terraform/*.json` files

## References

- AWS Bedrock AgentCore CLI documentation
- Terraform null_resource documentation
- Terraform external data source documentation

# AgentCore Foundation Module

## Overview
This module manages the base infrastructure for a Bedrock Agent, including the MCP Gateway, Workload Identity, and Observability stacks.

## Features
- **MCP Gateway**: Native AWS provider provisioning for the tool gateway and targets.
- **Identity**: ABAC-hardened IAM roles for agent workloads.
- **Observability**: CloudWatch Log Groups and X-Ray tracing.

## Regional Settings
- `region`: AgentCore control-plane region for gateway/identity/observability resources.
- `bedrock_region`: Optional Bedrock region override for model invocation permissions (defaults to `region`).

## Known Failure Modes (Rule 16)

### 1. Partial Provisioning (CLI Timeout)
- **Symptom**: `null_resource.workload_identity` fails mid-execution.
- **Impact**: Workload identity may be created but not recorded in SSM.
- **Recovery**:
  1. Manually identify the resource ID via AWS CLI: `aws bedrock-agentcore-control list-workload-identities`.
  2. Manually populate SSM: `aws ssm put-parameter --name "/agentcore/<agent_name>/identity/id" --value "<id>" --type "String" --overwrite`.
  3. Re-run `terraform apply`.

### 2. Zombie Workload Identity
- **Symptom**: `terraform destroy` fails to delete the workload identity.
- **Recovery**:
  1. Get ID from SSM: `aws ssm get-parameter --name "/agentcore/<agent_name>/identity/id"`.
  2. Manually delete: `aws bedrock-agentcore-control delete-workload-identity --workload-identity-identifier <id>`.
  3. Cleanup SSM: `aws ssm delete-parameter --name "/agentcore/<agent_name>/identity/id"`.

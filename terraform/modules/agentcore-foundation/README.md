# AgentCore Foundation Module

## Overview
This module manages the base infrastructure for a Bedrock Agent, including the MCP Gateway, Workload Identity, and Observability stacks.

## Features
- **MCP Gateway**: CLI-based provisioning of the tool gateway.
- **Identity**: ABAC-hardened IAM roles for agent workloads.
- **Observability**: CloudWatch Log Groups and X-Ray tracing.

## Known Failure Modes (Rule 16)

### 1. Partial Provisioning (CLI Timeout)
- **Symptom**: `null_resource.gateway` fails mid-execution.
- **Impact**: AWS resource may be created but not recorded in SSM.
- **Recovery**: 
  1. Manually identify the resource ID via AWS CLI: `aws bedrock-agentcore-control list-gateways`.
  2. Manually populate SSM: `aws ssm put-parameter --name "/agentcore/<agent_name>/gateway/id" --value "<id>" --type "String" --overwrite`.
  3. Re-run `terraform apply`.

### 2. Zombie Gateway
- **Symptom**: `terraform destroy` fails to delete the gateway.
- **Recovery**:
  1. Get ID from SSM: `aws ssm get-parameter --name "/agentcore/<agent_name>/gateway/id"`.
  2. Manually delete: `aws bedrock-agentcore-control delete-gateway --gateway-identifier <id>`.
  3. Cleanup SSM: `aws ssm delete-parameter --name "/agentcore/<agent_name>/gateway/id"`.

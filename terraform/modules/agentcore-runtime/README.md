# AgentCore Runtime Module

## Overview
This module manages the agent runtime, memory, and packaging process.

## Features
- **Two-Stage Packaging**: Local Python packaging and S3 upload.
- **Agent Runtime**: CLI-based provisioning of the agent control plane.
- **Memory**: Persistent agent memory configuration.
- **Inference Profiles**: Optional Bedrock application inference profile creation (CLI-based).

## Regional Settings
- `region`: AgentCore control-plane region for runtime/memory/packaging resources and SSM persistence.
- `bedrock_region`: Optional Bedrock region override for inference profile creation (defaults to `region`).

## Known Failure Modes (Rule 16)

### 1. Packaging Artifact Inconsistency
- **Symptom**: Agent fails to invoke because of missing dependencies.
- **Recovery**: 
  1. Manually clear the `.terraform/` directory in the module to force a re-package.
  2. Re-run `terraform apply`.

### 2. Runtime ID Mismatch
- **Symptom**: `null_resource.runtime` fails to update an existing agent.
- **Recovery**:
  1. Identify Agent ID: `aws bedrock-agentcore-control list-agents`.
  2. Synchronize SSM: `aws ssm put-parameter --name "/agentcore/<agent_name>/runtime/id" --value "<id>" ...`.

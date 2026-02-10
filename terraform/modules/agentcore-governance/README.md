# AgentCore Governance Module

## Overview
This module manages security and evaluation policies, including Cedar policy engines and Bedrock Guardrails.

## Features
- **Policy Engine**: Cedar-based authorization.
- **Guardrails**: Bedrock Guardrails for content filtering and PII redaction.
- **Evaluations**: Automated agent performance evaluation.

## Regional Settings
- `region`: AgentCore control-plane region for policy engine and evaluation resources.
- `bedrock_region`: Optional Bedrock region override for guardrails and evaluator model permissions (defaults to `region`).

## Known Failure Modes (Rule 16)

### 1. Guardrail Version Drift
- **Symptom**: `terraform apply` fails when creating a new guardrail version.
- **Recovery**: 
  1. Manually delete orphaned versions via CLI: `aws bedrock list-guardrail-versions`.
  2. If the guardrail ID in SSM is wrong, manually update it using the pattern in Rule 5.

### 2. Policy Engine Sync Failure
- **Symptom**: Cedar policies fail to attach to the engine.
- **Recovery**:
  1. Verify engine status: `aws bedrock-agentcore-control get-policy-engine`.
  2. If the engine is missing but SSM has an ID, delete the SSM parameter and re-apply.

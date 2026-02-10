# AgentCore Tools Module

## Overview
This module manages auxiliary tools for the agent, such as the Code Interpreter and Browser.

## Features
- **Code Interpreter**: Secure Python execution environment.
- **Browser**: Managed web browsing capabilities.

## Known Failure Modes (Rule 16)

### 1. VPC Configuration Sync
- **Symptom**: Code Interpreter fails to start due to networking issues.
- **Recovery**: 
  1. Verify Subnet and SG availability.
  2. If switching between PUBLIC and VPC modes, manually verify the tool status in Bedrock console or via CLI.

### 2. Orphaned Tool Resources
- **Symptom**: `terraform destroy` leaves tool-specific log groups or roles.
- **Recovery**:
  1. Manually identify tool resource: `aws bedrock-agentcore-control list-tools`.
  2. Delete via CLI and clear corresponding SSM parameters.

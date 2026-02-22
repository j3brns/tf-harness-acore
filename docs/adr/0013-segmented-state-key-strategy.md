# ADR 0013: Segmented Terraform State Key Strategy

## Status
Proposed

## Context
Currently, the repository uses a single, hardcoded state key for each environment (e.g., `agentcore/terraform.tfstate` in `backend-dev.tfvars.example`). This approach has several limitations:
1. **Multi-Tenancy Scale**: It prevents multiple independent deployments of AgentCore (different `app_id`s or `agent_name`s) within the same AWS account and S3 bucket without state collisions.
2. **Blast Radius**: A single state file for all components in an environment increases the risk of accidental modification or corruption affecting the entire platform.
3. **Alignment**: It does not align with the hierarchical identity model (Rule 14 and ADR 0012) which distinguishes between the human-facing `app_id` and the unique `agent_name`.

## Decision
We will implement a **segmented state key strategy** where each agent deployment has its own independent Terraform state file, partitioned by its logical and physical identity.

### State Key Pattern
The canonical state key for an AgentCore deployment is:
`state/${app_id}/${agent_name}/terraform.tfstate`

Where:
- `state/`: A common prefix to isolate Terraform state from other S3 data (like runtime memory or logs).
- `${app_id}`: The human-facing application alias (North anchor).
- `${agent_name}`: The unique, immutable internal identity of the agent (South anchor).

### Implementation Pattern
Since Terraform `backend` blocks do not support variables, we will use **Partial Backend Configuration**.

1. **Backend Block (Static)**:
   ```hcl
   terraform {
     backend "s3" {
       # bucket, region, and key are provided via -backend-config
       use_lockfile = true
       encrypt      = true
     }
   }
   ```

2. **Backend Configuration (Dynamic)**:
   A separate configuration file (e.g., `backend.tfvars`) or command-line arguments will be used during `terraform init`:
   ```bash
   terraform init 
     -backend-config="bucket=terraform-state-dev-12345" 
     -backend-config="key=state/my-app/research-agent-a1b2/terraform.tfstate" 
     -backend-config="region=eu-central-1"
   ```

## Rationale
- **Isolation**: Each agent's infrastructure is managed independently. A failure or mistake in one agent's state does not affect others.
- **Scalability**: Supports hundreds of independent agents within the same environment/account.
- **Multi-Tenancy**: Aligns the infrastructure state with the data partitioning strategy used at runtime (Rule 14).
- **Security**: Allows for more granular IAM policies on the state bucket, restricting access to specific agents if necessary.

## Consequences
### Positive
- Independent lifecycles for different agents.
- Reduced blast radius for state operations.
- Clear organization of infrastructure state in S3.
- Improved support for multi-tenant "shared compute" models where different apps share an account.

### Negative
- Requires a migration for existing deployments.
- `terraform init` becomes slightly more complex (requires passing backend config).
- Cross-agent dependencies (if any) must now use `terraform_remote_state` data sources, which are more explicit but require careful management.

## Alternatives Considered
1. **Terraform Workspaces**: Rejected (ADR 0006) - blast radius too large, difficult to manage across multiple accounts/regions.
2. **Terragrunt**: Terragrunt is a powerful tool that natively supports segmented state and backend generation. However, it was rejected for the core project to minimize external tool dependencies (Rule 7.5) and keep the development workflow aligned with pure Terraform CLI. Terragrunt remains a recommended wrapper for teams already using it in their ecosystem.

## Migration Strategy
Existing deployments at `agentcore/terraform.tfstate` will be migrated using the standard `terraform state pull/push` workflow, as documented in the [Segmented State Migration Runbook](../runbooks/segmented-state-migration.md).

## References
- [ADR 0004: State Management](./0004-state-management.md)
- [ADR 0006: Separate Backends](./0006-separate-backends.md)
- [ADR 0012: Agent Identity vs Alias](./0012-agent-identity-alias.md)
- [Rule 14: Multi-Tenant Isolation](../../GEMINI.md)

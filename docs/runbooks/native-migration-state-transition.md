# Runbook: CLI-to-Native Terraform State Transition (Workstream A / Issue #19)

## Purpose

This runbook defines the execution procedure for migrating a resource family from the repo's CLI bridge pattern (`null_resource` + AWS CLI) to native Terraform AWS provider resources without recreating the remote AWS object.

Scope for this runbook:
- Workstream A (`CLI -> Native`) state transitions only
- Execution issue support for roadmap item **A2**
- Dev-first migration flow (promotions are covered by roadmap item A3 / Issue #20)

Out of scope:
- Migrating resources still marked `cli-required` in `docs/NOVATION_MATRIX.md`
- Provider/schema design work for the native resource blocks themselves (covered in A1/A4 execution issues)

## Source of Truth and Guardrails

- Migration decision source of truth: `docs/NOVATION_MATRIX.md`
- Module boundaries are fixed (foundation -> tools/runtime -> governance): `docs/architecture.md`
- CLI pattern remains mandatory for the Rule 4 resource list unless the active execution issue explicitly migrates a family approved by the novation matrix.
- Run `make preflight-session` at session start and before commit/push (Rule 7.7).
- Keep one execution issue/worktree scoped to one migration unit (Rule 12.3-12.8).

## Key Rule: `import` vs `moved`

Use the right Terraform mechanism:

- `terraform import` / `import {}`:
  - Required for **CLI (`null_resource`) -> native (`aws_*`)** transitions.
  - This is a resource type change and cannot be handled as a simple address rename.
- `moved {}`:
  - Use only for **native-to-native address moves** (rename/resource-address reshaping) after the native resource exists in state.
  - Example: renaming `aws_bedrockagentcore_gateway.this` to `aws_bedrockagentcore_gateway.gateway`.

## Preconditions (Before Editing)

1. Confirm the target family is `native-now` in `docs/NOVATION_MATRIX.md`.
2. Confirm the migration is scoped to one execution issue/worktree.
3. Confirm the same environment inputs used in prior deploys (backend config, var-file, workspace/environment).
4. Confirm SSM-persisted IDs exist for the target CLI-managed resource(s).
5. Confirm no concurrent Terraform operation is running against the same backend.

## Pre-Flight Checklist (Mandatory)

Run from repo root unless noted.

1. Session/worktree safety

```bash
make preflight-session
```

2. Create scratch workspace for evidence (do not commit)

```bash
mkdir -p .scratch/migration
```

3. Capture current state backup (required before any import/state removal)

```bash
terraform -chdir=terraform state pull > .scratch/migration/$(date +%Y%m%d-%H%M%S)-pre-migration.tfstate
sha256sum .scratch/migration/*-pre-migration.tfstate
```

4. Drift check (refresh-only)

```bash
terraform -chdir=terraform plan \
  -refresh-only \
  -var-file=../examples/research-agent.tfvars
```

5. Baseline plan review (current branch before migration edit)

```bash
terraform -chdir=terraform plan \
  -var-file=../examples/research-agent.tfvars
```

Gate:
- Stop if the baseline plan shows unexpected drift or unrelated destroys.

## Migration Unit Strategy (Recommended)

Migrate one resource family at a time, in this order unless the execution issue states otherwise:

1. Foundation: Gateway, then Gateway Targets
2. Runtime: Agent Runtime, then Memory
3. Governance: Guardrail
4. Inference Profile (runtime-adjacent Bedrock resource)

Notes:
- `workload_identity` is tracked in the novation matrix, but the matrix currently notes native handling may be implicit/nested in other AgentCore resources. Treat it as a design-specific case in the execution issue; do not force a standalone import unless native resource/addressing is explicitly implemented.
- `browser`, `code_interpreter`, `policy_engine`, `cedar_policies`, and `custom_evaluator` remain `cli-required` per `docs/NOVATION_MATRIX.md`.

## Resource Family Mapping (Repo-Specific)

Use these addresses/ID sources when building import commands. Native addresses below are recommended naming conventions; if the implementation issue uses different names, adjust commands consistently and document the difference in the PR.

| Family | Current CLI State Address | Native Resource (Target) | Import ID Source | Import ID Format | `moved` Use |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Gateway | `module.agentcore_foundation.null_resource.gateway[0]` | `module.agentcore_foundation.aws_bedrockagentcore_gateway.gateway[0]` | SSM `/agentcore/<agent>/gateway/id` | gateway ID | Native rename only |
| Gateway Target (per key) | `module.agentcore_foundation.null_resource.gateway_target["<target_key>"]` | `module.agentcore_foundation.aws_bedrockagentcore_gateway_target.gateway_target["<target_key>"]` | SSM target ID + gateway ID | `gateway_id,target_id` | Native rename/key reshape only |
| Workload Identity | `module.agentcore_foundation.null_resource.workload_identity[0]` | Design-specific (may be nested/implicit in AgentCore native resources) | SSM `/agentcore/<agent>/identity/id` + `/identity/arn` | TBD by execution issue | `moved` not applicable until a concrete native address exists |
| Agent Runtime | `module.agentcore_runtime.null_resource.agent_runtime[0]` | `module.agentcore_runtime.aws_bedrockagentcore_agent_runtime.agent_runtime[0]` | SSM `/agentcore/<agent>/runtime/id` | runtime ID | Native rename only |
| Memory (short/long) | `module.agentcore_runtime.null_resource.agent_memory[0]` | `module.agentcore_runtime.aws_bedrockagentcore_memory.memory["short-term"]` / `["long-term"]` | SSM `/agentcore/<agent>/memory/<kind>/id` | memory ID | No direct CLI->native `moved` (type/cardinality change) |
| Guardrail | `module.agentcore_governance.null_resource.guardrail[0]` | `module.agentcore_governance.aws_bedrock_guardrail.guardrail[0]` | SSM `/agentcore/<agent>/guardrail/id` + `/guardrail/version` | `guardrail_id,version` | Native rename only |
| Inference Profile | `module.agentcore_runtime.null_resource.inference_profile[0]` | `module.agentcore_runtime.aws_bedrock_inference_profile.inference_profile[0]` | Configured profile name (verify against SSM ARN) | profile name | Native rename only |

## ID Retrieval Commands (From Existing CLI Pattern)

Replace `AGENT_NAME` and `REGION` with the deployed values.

```bash
export AGENT_NAME="<agent-name>"
export REGION="<region>"
```

Gateway:

```bash
aws ssm get-parameter \
  --name "/agentcore/${AGENT_NAME}/gateway/id" \
  --query 'Parameter.Value' \
  --output text \
  --region "${REGION}"
```

Gateway target (per target key):

```bash
TARGET_KEY="<mcp-target-key>"
aws ssm get-parameter \
  --name "/agentcore/${AGENT_NAME}/gateway/targets/${TARGET_KEY}/id" \
  --query 'Parameter.Value' \
  --output text \
  --region "${REGION}"
```

Runtime:

```bash
aws ssm get-parameter \
  --name "/agentcore/${AGENT_NAME}/runtime/id" \
  --query 'Parameter.Value' \
  --output text \
  --region "${REGION}"
```

Memory:

```bash
aws ssm get-parameter --name "/agentcore/${AGENT_NAME}/memory/short-term/id" --query 'Parameter.Value' --output text --region "${REGION}"
aws ssm get-parameter --name "/agentcore/${AGENT_NAME}/memory/long-term/id"  --query 'Parameter.Value' --output text --region "${REGION}"
```

Guardrail:

```bash
aws ssm get-parameter --name "/agentcore/${AGENT_NAME}/guardrail/id" --query 'Parameter.Value' --output text --region "${REGION}"
aws ssm get-parameter --name "/agentcore/${AGENT_NAME}/guardrail/version" --query 'Parameter.Value' --output text --region "${REGION}"
```

Inference profile (CLI path stores ARN; import uses name):

```bash
aws ssm get-parameter \
  --name "/agentcore/${AGENT_NAME}/inference-profile/arn" \
  --query 'Parameter.Value' \
  --output text \
  --region "${REGION}"

# Use the configured Terraform profile name for import (recommended):
#   var.inference_profile_name
```

## Execution Procedure (CLI -> Native Type Swap)

This is the standard pattern for a single family.

1. Implement the native resource block(s) in Terraform and disable/remove the corresponding CLI `null_resource` path in config for that family.
2. Add temporary `import {}` block(s) or prepare equivalent `terraform import` CLI commands.
3. Run plan and confirm the only expected change is import/state alignment (no unplanned destroys).
4. Import the existing remote object(s) into the native address(es).
5. Remove the legacy CLI state entry (`terraform state rm`) only after native import succeeds.
6. Re-run plan and confirm zero recreation for the migrated family.
7. Apply if the plan is clean and the execution issue authorizes dev apply.
8. Re-run plan/apply for idempotency (second apply must be no-op).

### Example A: Gateway (single resource)

```hcl
# Temporary import block (Terraform 1.5+)
import {
  to = module.agentcore_foundation.aws_bedrockagentcore_gateway.gateway[0]
  id = var._migration_gateway_id
}
```

```bash
# Or CLI import instead of import block:
terraform -chdir=terraform import \
  'module.agentcore_foundation.aws_bedrockagentcore_gateway.gateway[0]' \
  '<gateway-id>'

# Remove legacy CLI state node AFTER successful import
terraform -chdir=terraform state rm \
  'module.agentcore_foundation.null_resource.gateway[0]'
```

### Example B: Gateway Targets (`for_each`)

Gateway target imports need both the gateway ID and the target ID.

```bash
terraform -chdir=terraform import \
  'module.agentcore_foundation.aws_bedrockagentcore_gateway_target.gateway_target["tools"]' \
  '<gateway-id>,<target-id>'

terraform -chdir=terraform state rm \
  'module.agentcore_foundation.null_resource.gateway_target["tools"]'
```

Repeat per `mcp_targets` key. Do not batch-remove CLI target state before all native imports succeed.

### Example C: Memory (one CLI state node -> multiple native resources)

`null_resource.agent_memory[0]` may manage two remote memories (`short-term` and `long-term`). Import each native resource first, then remove the single CLI state node once all required memory imports succeed.

```bash
terraform -chdir=terraform import \
  'module.agentcore_runtime.aws_bedrockagentcore_memory.memory["short-term"]' \
  '<short-memory-id>'

terraform -chdir=terraform import \
  'module.agentcore_runtime.aws_bedrockagentcore_memory.memory["long-term"]' \
  '<long-memory-id>'

terraform -chdir=terraform state rm \
  'module.agentcore_runtime.null_resource.agent_memory[0]'
```

### Example D: Guardrail (versioned import)

```bash
terraform -chdir=terraform import \
  'module.agentcore_governance.aws_bedrock_guardrail.guardrail[0]' \
  '<guardrail-id>,<version>'

terraform -chdir=terraform state rm \
  'module.agentcore_governance.null_resource.guardrail[0]'
```

## `moved {}` Procedure (Native Address Refactor Only)

Use this after a family is already native if you rename resource blocks, move modules, or change `for_each` keys.

Example:

```hcl
moved {
  from = module.agentcore_foundation.aws_bedrockagentcore_gateway.this[0]
  to   = module.agentcore_foundation.aws_bedrockagentcore_gateway.gateway[0]
}
```

Rules:
- Add `moved {}` in the same commit as the address change.
- Keep it until the migration has been applied in all promoted environments covered by the execution issue.
- Do not use `moved {}` as a substitute for `import` when changing from `null_resource` to `aws_*`.

## Plan Review Gates (Stop/Proceed)

Proceed only if all are true:
- No unplanned destroy for the target family
- No unrelated changes outside the scoped module/family
- Imported native resource plan matches current remote settings (or expected drift fix is explicitly documented in the execution issue)
- Dependent modules still resolve outputs and references cleanly

Stop and fix if any of the following appear:
- Terraform wants to create a duplicate remote object instead of importing
- Terraform wants to destroy the CLI resource before native import is complete
- Target family plan touches `cli-required` resources
- Cross-module changes violate the fixed dependency order (foundation -> tools/runtime -> governance)

## Post-Flight Checks (Mandatory)

1. Idempotency

```bash
terraform -chdir=terraform plan \
  -var-file=../examples/research-agent.tfvars
```

Expected: no changes (or only approved, documented drift unrelated to the migrated family).

2. Second apply (if an apply was performed)

```bash
terraform -chdir=terraform apply \
  -var-file=../examples/research-agent.tfvars
```

Expected: no-op.

3. Smoke validation (pick the migrated family)
- Gateway: endpoint exists and MCP targets remain reachable
- Runtime: runtime ARN/ID outputs resolve and invoke path still works
- Memory: short/long memory IDs still resolve; no data loss symptoms
- Guardrail: guardrail ID/version outputs resolve; runtime attachments still plan/apply cleanly
- Inference Profile: profile ARN output unchanged or expected

4. Audit trail (required in issue/PR closeout)
- State backup filename + SHA256 (from `.scratch/migration/`)
- Imported resource addresses and IDs (redact only if sensitive; IDs are typically safe)
- Validation commands run and outcomes
- Commit SHA / PR link / CI links

## Rollback Procedure

If any step fails, choose the lowest-impact rollback that preserves the remote AWS object.

### Rollback A: Before Import (config-only)

- Revert the Terraform code changes.
- Re-run `terraform plan` to confirm the baseline is restored.

### Rollback B: After Native Import, Before Apply

- Remove native imported state entries:

```bash
terraform -chdir=terraform state rm '<native-address>'
```

- Revert code to the CLI implementation for that family.
- If state becomes inconsistent, restore from the pre-migration state backup (see `docs/runbooks/state-recovery.md`).

### Rollback C: After Apply (state/config regression)

1. Stop further applies.
2. Revert code to the last known-good commit.
3. Restore state from the pre-migration backup (or S3 version history) using `docs/runbooks/state-recovery.md`.
4. Run:

```bash
terraform -chdir=terraform plan \
  -var-file=../examples/research-agent.tfvars
```

5. Apply only after the plan matches the pre-migration expected state.

## Finish Protocol (Execution Issue)

Before commit/push for the migration execution issue:

1. Run `make preflight-session` (Rule 7.7)
2. Run issue-appropriate validation and capture outputs
3. Commit scoped changes with issue number in commit message
4. Push branch and open/update PR to `main`
5. Post issue closeout comment with validation evidence
6. Move issue status to `review` (Rule 12.8)

## References

- `docs/NOVATION_MATRIX.md`
- `docs/architecture.md`
- `docs/runbooks/state-recovery.md`
- `docs/adr/0002-cli-based-resources.md`
- `AGENTS.md` (Rules 4, 7.7, 7.8, 12.3-12.11)

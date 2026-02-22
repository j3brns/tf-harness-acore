# ADR 0012: Agent Identity vs Alias Naming

## Status
Accepted

## Context
`agent_name` is used as the seed for many AWS resource names (IAM roles, WAF, log groups, S3 buckets, SSM paths).
Human-friendly names (e.g., "agent1") are short, collision-prone, and change over time. Renaming `agent_name` forces
resource replacement and can break SSM lookups, cleanup hooks, and state continuity.

At the same time, operators need a readable, stable identifier for routing and tenancy. The repository already uses
`app_id` as the tenant-facing anchor in headers, DynamoDB PKs, and routing.

We need a clear, enforced convention to prevent collisions and avoid accidental destructive renames.

## Decision
1. **`agent_name` is the internal identity (immutable, unique).**
   - It MUST be unique per account/region.
   - It MUST include a suffix to prevent collisions.
2. **`app_id` is the human-facing alias.**
   - Used for routing, tenancy, and UI labeling.
   - Stable across deployments; does not change when internal IDs rotate.
3. **Naming convention for `agent_name`:**
   - Format: `word-word-word-xxxx` (or `word-word-word-env-xxxx`)
   - Suffix is 4-6 chars of lowercase base36/hex.
4. **Enforcement:**
   - Add a Terraform validation on `variable "agent_name"` to reject low-entropy names (e.g., `agent1`).
5. **Visibility:**
   - Tag resources with `AgentAlias = app_id` to keep the human label visible in AWS consoles.

## Consequences
### Positive
- Prevents name collisions and accidental overwrites.
- Avoids destructive renames for cosmetic changes.
- Keeps a stable, human alias for routing and tenant context.

### Negative
- Requires updating examples/templates and documentation.
- Adds validation that can block legacy configs until renamed.

## Implementation Notes
- Update `terraform/variables.tf` to enforce the naming convention for `agent_name`.
- Ensure templates and at least one example reflect the new convention (Rule 17, Rule 13).
- Update docs to clarify `agent_name` (internal) vs `app_id` (alias).

## Implementation Status
- Implemented in Issue #16 with root Terraform validation, example/template updates, canonical `AgentAlias` tagging, and a temporary legacy escape hatch (`allow_legacy_agent_name`) for migration safety.

## Migration Guidance
- Existing deployments should keep current `agent_name` to avoid replacement.
- New deployments should use the new pattern (three words + suffix) and set `app_id` to the human alias.

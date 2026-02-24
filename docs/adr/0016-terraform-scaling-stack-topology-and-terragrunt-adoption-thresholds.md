# ADR 0016: Terraform Scaling, Stack Topology, and Terragrunt Adoption Thresholds

## Status
Accepted

## Context

ADR 0013 defines the segmented backend key direction for reducing environment-level state lock contention:

- `agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate`

That addresses the first scaling bottleneck (environment-wide monolithic state), but it does not by itself solve the next set of scale problems:

- one root plan still touches many module domains (`foundation`, `tools`, `runtime`, `governance`, `bff`),
- CI pipeline scripts can accumulate repeated backend/provider/input wiring for multiple deployable units,
- developer inner loops degrade when small changes require broad plans or large review scopes,
- release autonomy becomes harder when app-team changes and platform-topology changes share the same Terraform execution surface.

This ADR establishes a pragmatic decision framework for scaling Terraform in this repo and defines when Terragrunt should be reconsidered as an orchestration layer.

## Decision

### 1. Terraform Remains the Primary Execution Engine

The repository standard remains plain Terraform for module implementation and state operations.

- Terraform modules remain the source of truth for infrastructure behavior.
- CI jobs continue to run Terraform commands directly for plan/apply/validation.
- Terragrunt (if adopted later) is an orchestration/helper layer only, not a replacement for Terraform modules.

### 2. Scale Terraform First Before Adopting Terragrunt

The default path is to improve Terraform scalability in this order:

1. **State segmentation** (ADR 0013) by deployable identity (`env + app_id + agent_name`).
2. **Stack topology separation** so plans/applies are scoped to a deployable surface.
3. **CI scoping** so pipelines plan/apply only the intended stack.
4. **Measured evaluation** of remaining orchestration pain.
5. **Terragrunt adoption decision** only if thresholds are exceeded (Section 5).

Terragrunt is not introduced simply because the repo grows; it is introduced only when measured orchestration overhead remains high after Steps 1-3.

### 3. Stack Topology Strategy (Terraform-First)

#### 3.1 Stack Boundaries (Target)

Use stack boundaries aligned to architectural and release autonomy boundaries. The canonical stack categories are:

- `foundation` (gateway, identity, observability, inference profile)
- `bff` (API Gateway, auth handlers, proxy, CloudFront, sessions, audit logs)
- `runtime` (runtime package/runtime deployment/memory)
- `governance` (policies, evaluators, guardrails)
- `tools` (browser, code interpreter)

The exact stack split may be introduced incrementally. A single app/agent may initially keep some categories co-located while the pilot proves the model.

#### 3.2 Stack State Keys (Extension of ADR 0013)

If a single `app_id + agent_name` pair is split into multiple independently planned/applied stacks, append a stack segment to the key:

```text
agentcore/{env}/{app_id}/{agent_name}/{stack}/terraform.tfstate
```

Examples:
- `agentcore/dev/research-console/research-agent-core-a1b2/foundation/terraform.tfstate`
- `agentcore/dev/research-console/research-agent-core-a1b2/bff/terraform.tfstate`

This stack segment is an extension of ADR 0013, not a replacement.

#### 3.3 Inner Loop Constraint (Non-Negotiable)

Scaling changes MUST preserve a fast local developer loop:

- module development and validation must remain possible with direct Terraform commands,
- local `terraform init -backend=false` and `terraform validate` must remain supported,
- template/scaffold iteration must not require full multi-stack orchestration.

### 4. Release Autonomy and Ownership Boundaries

Stack topology and CI scoping MUST align to release autonomy boundaries:

- Platform-owned shared surfaces (CI templates, state topology, shared auth/promotion controls) require platform review and migration evidence.
- App/team-owned stacks should be plan/applyable without unrelated platform stack changes.
- CI/release-plane actors govern environment promotion and evidence only; they do not become runtime tenant authorization authorities.

### 5. Terragrunt Adoption Thresholds (Criteria-Based)

Terragrunt SHOULD be re-evaluated only when one or more of the following thresholds are met after Terraform-first scaling has been applied:

1. **Backend/provider/input duplication threshold**
- The same backend/provider/env wiring logic is duplicated across 3+ stack entrypoints and repeated edits cause defects or drift.

2. **Stack orchestration threshold**
- CI regularly executes 3+ ordered stack plans/applies with ad hoc dependency scripting that is hard to reason about or repeatedly breaks.

3. **Overlay complexity threshold**
- Environment/app/agent overlays require deep tfvars layering that is causing review confusion or incorrect deployments.

4. **Operator burden threshold**
- Migration or recovery procedures require repeated manual key/path calculations across many stacks and teams.

5. **Developer inner-loop threshold**
- Developers cannot perform scoped stack validation quickly because wrapper/setup steps dominate the iteration cycle.

Meeting a threshold does not automatically force Terragrunt adoption. It triggers a documented evaluation and pilot.

### 6. Terragrunt Scope Constraints (If Adopted)

If Terragrunt is adopted in a future issue, it MUST be limited to orchestration concerns:

Allowed uses:
- backend configuration generation
- provider/input inheritance for env/app/agent overlays
- dependency ordering between stack entrypoints
- CI command simplification for multi-stack execution

Forbidden or discouraged uses:
- embedding business logic that belongs in Terraform modules
- hiding module contracts behind opaque wrapper conventions
- making direct Terraform module validation impossible
- replacing documented module architecture boundaries with Terragrunt layout conventions

### 7. Pilot and Rollback Requirements

Any Terragrunt evaluation or adoption pilot MUST include:

- one scoped app/agent pilot only,
- measured before/after metrics (plan time, changed resources, job count, operator steps),
- documented rollback to Terraform-only orchestration,
- inner-loop verification (local module validation and template smoke tests remain cheap),
- security/compliance review of generated backend/provider configs.

## Consequences

### Positive
- Preserves Terraform familiarity and current CI behavior while addressing scaling risks incrementally.
- Reduces pressure to adopt a new orchestration tool before state and stack boundaries are defined.
- Provides an evidence-based path to Terragrunt if/when orchestration complexity justifies it.
- Keeps local developer iteration fast and predictable.

### Negative
- Requires more architectural discipline in stack boundaries and ownership mapping.
- Introduces an additional decision framework that must be followed consistently.
- A phased Terraform-first approach may defer some DRY benefits Terragrunt can provide.

## Risks and Mitigations

- **Risk: partial stack split without clear ownership causes more confusion than a monolith**
  - Mitigation: require explicit stack ownership, outputs/inputs, and CI scoping per pilot.

- **Risk: state-key expansion creates migration complexity**
  - Mitigation: follow ADR 0013 + segmented state migration runbook; migrate one environment at a time.

- **Risk: Terragrunt gets adopted as a workaround for poor module contracts**
  - Mitigation: require module contract review and inner-loop validation proof before adoption decision.

## Senior Review Checkpoints (Mandatory for Tracker/Epic-Level Changes)

1. **Pass 1 (Architecture/Kickoff)**
- Review stack boundary proposal, ownership mapping, and threshold rationale before implementation starts.

2. **Pass 2 (Pilot/Closeout)**
- Review measured pilot evidence, inner-loop impact, CI reliability impact, and rollback viability before broad rollout.

## References

Repo sources:
- `docs/adr/0013-segmented-state-key-strategy.md`
- `docs/runbooks/segmented-terraform-state-key-migration.md`
- `docs/adr/0014-metadata-tagging-telemetry-and-release-metadata-boundaries.md`
- `docs/adr/0015-bff-identity-persistence-interceptors-and-multitenancy-viability.md`
- `docs/runbooks/tenant-platform-architecture-build-plan.md`

Primary external references (checked 2026-02-23):
- HashiCorp Terraform backend partial configuration:
  - https://developer.hashicorp.com/terraform/language/backend#partial-configuration
- HashiCorp Terraform S3 backend:
  - https://developer.hashicorp.com/terraform/language/backend/s3
- HashiCorp Terraform module structure guidance:
  - https://developer.hashicorp.com/terraform/language/modules/develop/structure
- Terragrunt documentation (blocks/features, includes/dependencies):
  - https://terragrunt.gruntwork.io/docs/reference/hcl/blocks/
- Gruntwork/Terragrunt overview and DRY orchestration guidance:
  - https://www.gruntwork.io/open-source/terragrunt

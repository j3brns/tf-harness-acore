# Runbook: Terraform Scaling, Stack Segmentation, and Terragrunt Pilot Evaluation

## Purpose

Provide a repeatable, low-risk procedure to:

1. validate Terraform-first scaling improvements (state segmentation + stack scoping), and
2. decide whether Terragrunt is justified for orchestration in this repo.

This runbook implements ADR 0016 and complements ADR 0013 state-key migration guidance.

## Scope

In scope:
- pilot stack topology for one app/agent boundary,
- state key segmentation extension with optional `{stack}` suffix,
- CI scoped plan/apply validation for the pilot,
- inner-loop measurement (local validation speed and developer friction),
- Terragrunt pilot (optional, criteria-triggered) for orchestration only.

Out of scope:
- full repo-wide rollout in one change,
- changing runtime tenant authorization behavior,
- rewriting Terraform modules into Terragrunt logic,
- mixed refactors unrelated to state/stack/orchestration scale.

## Preconditions

- ADR 0013 and ADR 0016 are accepted and current.
- A tracker issue exists for the scaling initiative (Rule 12.3 tracker/execution split).
- A designated pilot app/agent pair is chosen and documented.
- `make preflight-session` passes in the working session.

## Pilot Success Criteria

A pilot is successful when all of the following are true:

- Scoped plan/apply targets only the intended stack state and resources.
- State key(s) are human-readable and collision-free.
- Inner-loop local validation remains cheap (`terraform init -backend=false`, `terraform validate`, template smoke tests).
- CI evidence shows scoped jobs and preserved promotion controls.
- Rollback instructions are tested as documented dry-run steps.
- Senior review Pass 1 and Pass 2 are recorded.

## Phase 1: Baseline (Before Changes)

Record baseline metrics for one representative app/agent deployment:

- Terraform plan duration (dev/test)
- Number of resources in plan for a narrow change
- CI jobs executed for plan/apply/promotion
- Manual operator steps for backend key selection/recovery
- Developer inner-loop commands and elapsed time
- Shared files touched for a narrow runtime-only change

Record baseline evidence in the tracker issue:
- commit SHA
- pipeline links (GitHub/GitLab)
- command outputs (summarized)

## Phase 2: Define Stack Boundary Proposal

For the pilot app/agent, propose the initial stack split:

- `foundation`
- `bff`
- `runtime`
- `governance`
- `tools` (optional if deferred)

Document per stack:
- ownership (platform vs app team)
- inputs/outputs
- expected touched paths
- CI jobs that will plan/apply it
- state key pattern

### Recommended Pilot Starting Point

Use a minimal two-stack split first if risk is high:
- `foundation+bff` (platform-heavy shared ingress/auth surfaces)
- `runtime+governance` (app/runtime behavior surfaces)

Then refine into canonical stack categories after proving CI and state behavior.

## Phase 3: State Key Segmentation (Pilot)

### 3.1 Choose Key Pattern

If stacks remain co-located for the pilot:

```text
agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate
```

If independent stacks are introduced during the pilot:

```text
agentcore/{env}/{app_id}/{agent_name}/{stack}/terraform.tfstate
```

### 3.2 CI Input Contract (Required)

Ensure CI can render keys before `terraform init` using non-secret inputs:
- `CI_ENVIRONMENT_NAME`
- `TF_STATE_APP_ID`
- `TF_STATE_AGENT_NAME`
- `TF_STATE_STACK` (only if using stack suffix)

Guardrails:
- fail fast on missing inputs,
- normalize to slug-safe values,
- log the rendered key (non-secret) in the job output.

### 3.3 Migration Safety

Follow `docs/runbooks/segmented-terraform-state-key-migration.md` for actual migration operations.

For stack-suffix adoption, perform migration one stack at a time and prevent concurrent applies against the affected state during cutover.

## Phase 4: CI Scoping and Trust-but-Verify

### 4.1 Scoped CI Jobs

For each pilot stack, verify CI jobs:
- plan only the target stack,
- apply only the target stack,
- preserve existing promotion gates and manual approvals,
- emit evidence links and rendered backend key context.

### 4.2 Regression vs Debt Triage

If CI fails during the pilot:
- classify failures as **pilot regression** vs **pre-existing debt**,
- fix pilot regressions in-scope,
- track pre-existing debt separately unless it blocks safe rollout.

### 4.3 Verification Evidence (Required)

Record in tracker and execution issues:
- rendered backend key(s)
- plan/apply scope evidence
- validation commands run
- CI URLs (GitHub + GitLab)
- rollback dry-run evidence

## Phase 5: Inner Loop and Template Dev Guardrails

The pilot MUST preserve a cheap local development loop.

Required local checks:

```bash
terraform -chdir=terraform init -backend=false -input=false
terraform -chdir=terraform validate
make template-smoke
```

Template development guardrails:
- use fast smoke tests locally before pushing template changes,
- avoid forcing frontend/browser-heavy checks for every template iteration,
- keep security posture by validating Terraform render output and placeholder elimination.

## Phase 6: Terragrunt Evaluation (Only if ADR 0016 Thresholds Trigger)

Run this phase only if ADR 0016 thresholds are met after Terraform-first scaling improvements.

### 6.1 Evaluation Questions

- Is backend/provider/env wiring duplication materially reduced by Terragrunt in this repo?
- Does Terragrunt improve CI readability and dependency ordering for multi-stack workflows?
- Does Terragrunt preserve (or improve) inner-loop speed for module developers?
- Does it increase migration/troubleshooting complexity beyond acceptable limits?

### 6.2 Pilot Constraints (If Run)

- one app/agent pilot only,
- orchestration-only scope (backend generation / includes / dependencies),
- no business logic moved out of Terraform modules,
- direct Terraform validation commands remain documented and functional.

### 6.3 Rollback (Mandatory)

Document and test rollback to Terraform-only orchestration:
- remove Terragrunt wrapper invocation in CI for the pilot stack,
- restore Terraform CLI commands and backend rendering,
- verify state key continuity,
- validate plan/apply outputs match expected stack scope.

## Senior Review Passes (Mandatory)

### Pass 1: Architecture / Kickoff
Review before pilot implementation starts:
- stack boundary proposal
- ownership and autonomy boundaries
- state key pattern
- CI scoping plan
- risk register and rollback plan

### Pass 2: Pilot / Closeout
Review before rollout decision:
- measured before/after metrics
- CI reliability impact
- inner-loop impact on template and module development
- evidence quality (GitHub/GitLab CI, issue/PR closeout)
- Terragrunt adopt/defer recommendation (if evaluated)

## Exit Outcomes

Choose one and record evidence:

1. **Terraform-only scaling accepted**
- state/stack scoping is sufficient,
- Terragrunt deferred with evidence.

2. **Terragrunt pilot justified**
- thresholds exceeded,
- pilot approved under ADR 0016 constraints.

3. **Rework required**
- stack boundaries or CI scoping model insufficient,
- revise architecture before further rollout.

## References

- `docs/adr/0013-segmented-state-key-strategy.md`
- `docs/adr/0016-terraform-scaling-stack-topology-and-terragrunt-adoption-thresholds.md`
- `docs/runbooks/segmented-terraform-state-key-migration.md`
- `docs/runbooks/tenant-platform-architecture-build-plan.md`
- `terraform/tests/validation/template_scaffold_smoke_test.sh`

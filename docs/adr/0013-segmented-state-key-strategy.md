# ADR 0013: Segmented Terraform State Key Strategy (E8A)

## Status
Accepted

## Context

Current GitLab CI backend generation creates one Terraform state key per environment:

- `agentcore/${CI_ENVIRONMENT_NAME}/terraform.tfstate`

This is simple, but it creates unnecessary lock contention and blast radius when multiple
agents/services are managed in parallel within the same environment backend bucket/account.

E8A is the architecture/decision phase for workstream E8. It must:
- define a target key segmentation strategy,
- define CI-safe inputs available before `terraform init`,
- provide a migration-safe runbook,
- evaluate Terragrunt for this repo (adopt/defer),
- hand off implementation-ready requirements to E8B (`#74`),
- clarify region assumptions without changing region defaults.

## Decision

### 1. Target Backend Key Strategy (Chosen)

Use a finer-grained key segmented by environment + application alias + agent identity:

```text
agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate
```

Examples:
- `agentcore/dev/research-console/research-agent-core-a1b2/terraform.tfstate`
- `agentcore/test/ops-assistant/ops-assistant-core-f9e1/terraform.tfstate`

Rationale:
- `env` preserves the current explicit environment boundary.
- `app_id` groups state by logical application (North anchor).
- `agent_name` prevents collisions for multiple physical agents under one app.
- The resulting path is human-readable for recovery and audit workflows.

### 2. Candidate Patterns Considered (Criteria-Based)

| Pattern | Pros | Cons | Decision |
| --- | --- | --- | --- |
| `agentcore/{env}/terraform.tfstate` (current) | Minimal inputs, simple | Lock contention across all stacks in env; poor isolation | Reject as target (keep only as migration source) |
| `agentcore/{env}/{app_id}/terraform.tfstate` | Better grouping; simple | Collides when an app deploys multiple agents/stacks | Reject as default |
| `agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate` | Strong isolation, readable, CI-derivable | Requires two new CI-safe identity inputs | **Adopt** |
| `agentcore/{env}/{region}/{app_id}/{agent_name}/terraform.tfstate` | Avoids some multi-region collisions | Region ambiguity in split-region topology (`agentcore_region` vs `bff_region` vs `bedrock_region`) | Defer (optional future extension) |

### 3. CI Input Contract (Required Before `terraform init`)

E8B (`#74`) must derive the backend key before Terraform backend initialization. The minimum CI inputs are:

- Existing:
  - `CI_ENVIRONMENT_NAME` (environment boundary)
  - `TF_STATE_BUCKET` (target backend bucket)
  - `AWS_DEFAULT_REGION` (backend bucket access region)
- New (or explicitly mapped from existing job inputs):
  - `TF_STATE_APP_ID` (slug-safe application identifier; typically aligns to `TF_VAR_app_id`)
  - `TF_STATE_AGENT_NAME` (slug-safe physical agent identifier; typically aligns to `TF_VAR_agent_name`)

Derived backend key:

```text
agentcore/${CI_ENVIRONMENT_NAME}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate
```

Guardrails for E8B:
- Fail fast if `TF_STATE_APP_ID` or `TF_STATE_AGENT_NAME` is unset/empty.
- Normalize/sanitize to backend-key-safe slugs before rendering.
- Log the rendered key (without secrets) before `terraform init`.
- Keep a temporary escape hatch for the legacy env-only key during phased migration.

### 4. Migration Strategy (Architecture Handoff)

Migrate state keys from the current env-only pattern:

```text
agentcore/${CI_ENVIRONMENT_NAME}/terraform.tfstate
```

to the new segmented pattern using a controlled backend migration (no manual state edits):
- one environment at a time (`dev` -> `test` -> `prod`),
- `terraform init -reconfigure -migrate-state`,
- pre/post validation and rollback steps recorded,
- no concurrent pipelines against the same backend during the migration window.

Execution runbook:
- `docs/runbooks/segmented-terraform-state-key-migration.md`

### 5. Terragrunt Evaluation (Decision: Defer / No Adopt for E8B)

Terragrunt was evaluated for backend key DRYness and tfvars layering. E8A decision:

- **Defer Terragrunt adoption** for E8B and this migration.

Criteria-based rationale:
- **Backend key generation / DRYness:** Terragrunt helps, but E8B only needs a targeted CI template change in existing `.gitlab-ci.yml`.
- **tfvars layering / per-agent overrides:** Terragrunt provides value, but adopting it would change operator workflows and repo conventions beyond E8B scope.
- **GitLab promotion gate compatibility:** Current pipeline gating (`promote:test`, `plan:test`, `deploy:test`, `smoke-test:test`) is already implemented and validated around plain Terraform commands.
- **Migration complexity / operator overhead:** Introducing Terragrunt while changing backend keys materially increases rollout risk and troubleshooting surface area.
- **Rule 7 sprawl control fit:** Terragrunt would likely add new wrapper files/layout conventions across the repo, conflicting with E8B's goal of a focused CI/backend key migration.

Re-evaluate Terragrunt in a separate issue if the repo later needs broader environment composition, deep tfvars layering, or cross-stack orchestration.

### 6. Region Clarification (E8A Constraint, No Default Change)

E8A does **not** change the repo region model.

- `.gitlab-ci.yml` currently defaults `AWS_DEFAULT_REGION` to `eu-west-2` (used for backend config generation and general AWS CLI context).
- AgentCore control-plane/runtime placement remains an explicit deployment input (`agentcore_region`) and may differ from `AWS_DEFAULT_REGION`.
- Split-region deployments remain supported (`agentcore_region`, `bedrock_region`, `bff_region`) and are documented in `docs/runbooks/eu-split-deployment.md`.
- CloudFront global exceptions remain explicit (for example ACM certs and CloudFront-scope WAF in `us-east-1`) and are outside the AgentCore regional availability matrix.

State-key implication:
- The default key strategy intentionally omits a region segment because one Terraform state can manage split-region resources.
- Region-aware keying can be revisited only if a concrete collision scenario is observed and a single region scope is unambiguous.

### 7. E8B (`#74`) Handoff Inputs and Acceptance

E8B can proceed when implementing only CI/backend behavior changes (no architecture re-decision):

Required implementation outputs for E8B:
- CI backend key rendering updated to use the new segmented pattern.
- Explicit CI input validation for `TF_STATE_APP_ID` and `TF_STATE_AGENT_NAME`.
- Migration sequencing plan applied per environment using the runbook.
- Operator-visible evidence for rendered keys (at least two env/app/agent combinations).
- Rollback path documented in PR and tested as a documented dry-run.

E8B must not:
- silently change region defaults,
- introduce Terragrunt as part of the backend-key migration,
- mix unrelated CI refactors into the same execution PR.

## Consequences

### Positive
- Reduced lock contention and blast radius within each environment.
- Cleaner S3 object organization for recovery and audits.
- CI behavior remains Terraform-native and minimally invasive.
- Clear architecture handoff to E8B without implementation ambiguity.

### Negative
- CI now depends on two additional identity inputs before `terraform init`.
- Migration requires careful sequencing and temporary dual-key awareness.
- More verbose backend key paths and recovery commands.

## References

Repo sources:
- `.gitlab-ci.yml` (backend generation template)
- `docs/runbooks/segmented-terraform-state-key-migration.md`
- `docs/runbooks/eu-split-deployment.md`
- `docs/adr/0007-single-region-decision.md`
- `.context/e8a-agentcore-regional-availability-matrix-2026-02-22.md`

Issue handoff:
- `#73` (E8A architecture/decision)
- `#74` (E8B implementation)

AWS sources (AWS Knowledge MCP-backed in E8A):
- https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html
- https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/cross-region-inference.html
- https://docs.aws.amazon.com/general/latest/gr/bedrock_agentcore.html

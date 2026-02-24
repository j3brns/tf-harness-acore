# Tenant Platform Architecture Build Plan (Identity, Multi-Tenancy, Observability, Cost, Release Autonomy)

## Purpose

Track the implementation program for the architecture defined/clarified by:
- `docs/adr/0014-metadata-tagging-telemetry-and-release-metadata-boundaries.md`
- `docs/adr/0015-bff-identity-persistence-interceptors-and-multitenancy-viability.md`

This plan keeps the work decomposed into buildable slices and prevents "architecture complete" claims before the
runtime, observability, cost, and release-plane mechanisms are implemented and tested.

## Scope (This Plan Covers)

- BFF tenant API identity persistence and interceptor boundaries
- Tenant/session metadata telemetry contract (logs, audit records, traces)
- Cost management via Application Inference Profiles + tenant attribution joins
- Tenant-partitioned dashboards (ops + analytics split)
- GitLab group/project release autonomy model and evidence mapping
- Local inner-loop parity for identity/tenancy/observability validation
- Terraform state scaling follow-through (segmented key adoption and anti-monolith posture)

## Out of Scope (Track Separately)

- New product features unrelated to tenancy/identity/observability/cost/release autonomy
- UI/portal feature polish not required to validate tenancy or auditability
- Full tenant-dedicated runtime topologies unless a specific tenant/compliance requirement demands them

## Planning Assumptions (Check and Update)

- Check date for AWS quota/service guidance references in ADR 0015: **2026-02-23**
- Current repo baseline uses BFF + API Gateway + DynamoDB session store + audit shadow logs + Athena metadata
- Terraform state monolith (`agentcore/<env>/terraform.tfstate`) may still exist in some pipelines/environments and is treated as a migration baseline, not the scaling target

## Architecture Program Phases

### Phase A: Identity Persistence and Tenant Safety (Foundational)

Goal: make tenant identity propagation and session binding explicit, testable, and auditable.

Deliverables:
- [ ] BFF interceptor/handler contract documented in implementation-facing code/docs
- [ ] Identity envelope field schema agreed and documented (`app_id`, `tenant_id`, principal, `session_id`, correlation IDs)
- [ ] Inbound/outbound identity distinction reflected in BFF and/or gateway integration code paths
- [ ] Negative tests for tenant override attempts (request-body tenant spoofing)
- [ ] Session binding validation tests (`app_id + tenant_id + principal` continuity)

Acceptance evidence:
- unit/integration tests for identity normalization + session binding
- docs references updated (README/DEVELOPER_GUIDE/runbook as needed)
- trace/log samples showing normalized tenant/app/session fields

Primary risks:
- duplicate or inconsistent auth checks between BFF and Gateway
- hidden trust of request-body tenant fields
- CI-plane metadata leaking into runtime authz logic

### Phase B: Observability and Tenant Auditability

Goal: make tenant-aware observability reliable without high-cardinality metric anti-patterns.

Deliverables:
- [ ] Canonical structured log field contract adopted in BFF/auth/proxy code
- [ ] Trace annotation contract adopted (tenant-aware, secret-safe)
- [ ] Audit log schema validation/tests (required fields present)
- [ ] Tenant dashboard query pack (Athena) for volume/errors/latency by tenant
- [ ] Ops dashboard vs tenant analytics dashboard split documented

Acceptance evidence:
- example Athena queries and expected results
- trace screenshots or trace query examples using tenant/app/session annotations
- validation tests for audit log field presence and schema consistency

Primary risks:
- trace/log field drift across services
- per-tenant metric cardinality explosion in CloudWatch
- secrets accidentally captured in logs/traces

### Phase C: Cost and Authorization Boundary Hardening

Goal: make cost attribution and model authorization boundaries align with App/Agent identities.

Deliverables:
- [ ] Inference profile usage policy documented for applicable runtimes/evaluators
- [ ] Inference profile tags standardized (canonical + extended cost tags)
- [ ] Cost attribution join method documented (inference profile + audit telemetry)
- [ ] IAM scoping updated to prefer inference profile ARN where supported
- [ ] Cost dashboard/query proof of concept (app/agent-level; tenant-derived allocation model documented)

Acceptance evidence:
- runtime/evaluator path docs or code references showing profile usage
- Terraform variable examples for `enable_inference_profile` + `inference_profile_tags`
- sample cost attribution query/report methodology

Primary risks:
- partial adoption causing mixed cost boundaries
- tenant-level chargeback claims without sufficient telemetry fidelity

### Phase D: Release Autonomy and GitLab Governance

Goal: enable dev-team autonomy in lower environments while preserving platform controls and evidence.

Deliverables:
- [ ] GitLab group/project ownership model documented (platform group vs team projects)
- [ ] Protected environments/tags and approver responsibilities documented
- [ ] Promotion evidence schema standardized (pipeline ID, approver, promoted SHA lineage)
- [ ] Runtime authorization docs explicitly decoupled from CI/release metadata
- [ ] Example project/tag metadata mirrored into Terraform tagging guidance (where applicable)

Acceptance evidence:
- release governance runbook or README/DEVELOPER_GUIDE update
- example promotion evidence entry in issue/PR closeout template
- explicit docs statement that CI/release metadata is not runtime tenant auth input

Primary risks:
- overloading CI metadata into runtime decisions
- unclear team/platform ownership boundaries causing blocked releases

### Phase E: Inner Loop and Local Dev Parity

Goal: make identity/tenancy/observability behavior testable locally before GitLab deploy loops.

Deliverables:
- [ ] OIDC claim fixtures for local tests (Entra-shaped claims normalized to internal envelope)
- [ ] Local interceptor unit tests (inbound + outbound)
- [ ] Session-binding local tests with positive/negative cases
- [ ] Structured audit sample fixtures for tenant dashboard query development
- [ ] Local dev docs for replaying BFF/API or MCP interactions while preserving metadata contract

Acceptance evidence:
- local test commands and passing outputs
- docs/runbook snippets for local replay workflows
- fixture examples checked into tests/examples (not `.scratch/`)

Primary risks:
- cloud-only validation loop slows development and causes unsafe shortcuts
- local fixtures diverge from production field names

### Phase F: Terraform State/Stack Scaling and Terragrunt Decision Gate

Goal: scale Terraform execution surfaces and CI orchestration without sacrificing local development speed.

Deliverables:
- [ ] ADR 0013 segmented state key strategy implemented in target pipelines/environments
- [ ] Stack topology pilot defined and measured (Terraform-first)
- [ ] `make template-smoke` (fast) and `make template-smoke-full` (trust-and-verify) adopted for template/scaffold validation
- [ ] CI trust-but-verify evidence for scoped plan/apply and backend key rendering captured
- [ ] Terragrunt adopt/defer decision recorded with thresholds/evidence per ADR 0016

Acceptance evidence:
- pilot metrics before/after (plan scope, job count, operator steps)
- backend key rendering evidence in CI logs (non-secret)
- local inner-loop and trust-and-verify outputs (`terraform validate`, `make template-smoke`, `make template-smoke-full`)
- senior review pass 1 and pass 2 notes linked in the tracker

Primary risks:
- partial stack split increases complexity without clear ownership
- Terragrunt adopted prematurely as a workaround for weak module contracts
- inner-loop cost increases and slows template/stack iteration

## Cross-Cutting Scaling Parameters and Architecture Risks

These risks MUST be checked during implementation and release planning, not only after incidents:

- **Terraform state monolith risk**: env-only state key causes lock contention and shared blast radius
  - Mitigation: segmented state keys (`env/app_id/agent_name`) per ADR 0013
- **API Gateway scaling/quotas**: route/resource/authorizer/throttle quotas can constrain tenant growth and BFF route sprawl
  - Mitigation: compact route surface, quota checks, authorizer reuse
- **Cloud Map discovery throttling**: `DiscoverInstances` overuse can throttle East-West agent mesh traffic
  - Mitigation: cache + backoff + namespace/service partitioning
- **DynamoDB hot partition risk** in pooled tenants
  - Mitigation: access-pattern validation, tenant-aware key design, write sharding when needed
- **Observability cardinality cost**: per-tenant CloudWatch dimensions do not scale cleanly
  - Mitigation: Athena/BI for tenant analytics; CloudWatch/X-Ray for ops health

## Viability Gates (Reality Check)

Before claiming "pooled multi-tenancy ready" for a stack, all of the following MUST be true:
- [ ] `tenant_id` derived from validated identity context (not request body trust)
- [ ] session binding enforced and tested
- [ ] ABAC/policy checks enforce tenant/resource match
- [ ] persistent data partitioning follows `AppID + TenantID` model
- [ ] audit logs include `app_id`, `tenant_id`, `session_id`, outcomes
- [ ] traces correlate tenant/app/session safely (no secret leakage)
- [ ] negative tests prove cross-tenant access rejection

## Worktree / Issue Execution Guidance (How to Run the Program)

- Use `make worktree` to allocate execution issues from the `ready` queue.
- Worktree handoff prompts should point agents to:
  - `docs/architecture.md`
  - `docs/adr/0014-...`
  - `docs/adr/0015-...`
  - this plan file
- Prefer tracker + execution issue splits for phases that mix architecture and implementation.
- Keep BFF identity/interceptor work, cost attribution work, and release-plane governance work in separate execution issues unless explicitly coordinated.

## Suggested First Execution Sequence (Pragmatic)

1. **Phase A (Identity Persistence + Interceptors)**
   - unlocks reliable tenant authz, trace correlation, and downstream policy enforcement
2. **Phase B (Observability + Tenant Auditability)**
   - proves tenant attribution and supports incident/ops visibility
3. **Phase C (Inference Profile Cost/Auth Boundary)**
   - aligns cost and IAM scoping with app/agent identity
4. **Phase D (GitLab Release Autonomy)**
   - reduces delivery friction while preserving platform controls
5. **Phase E (Local Inner Loop Parity)**
   - parallelize early where possible, but ensure fixtures/contracts stabilize first
6. **Phase F (Terraform State/Stack Scaling + Terragrunt Decision Gate)**
   - pilot after identity/observability boundaries are clear enough to measure scoped execution and autonomy

## Review Cadence

- Re-review this plan when any of these change:
  - ADR 0014 metadata-plane rules
  - ADR 0015 interceptor or multitenancy viability model
  - Terraform state topology strategy (ADR 0013)
  - GitLab promotion model or environment/tag protection rules
  - BFF audit schema field contract
  - Terraform stack topology / Terragrunt adoption thresholds (ADR 0016)

## References

- `docs/architecture.md`
- `docs/adr/0013-segmented-state-key-strategy.md`
- `docs/adr/0014-metadata-tagging-telemetry-and-release-metadata-boundaries.md`
- `docs/adr/0015-bff-identity-persistence-interceptors-and-multitenancy-viability.md`
- `docs/adr/0016-terraform-scaling-stack-topology-and-terragrunt-adoption-thresholds.md`
- `docs/runbooks/segmented-terraform-state-key-migration.md`
- `docs/runbooks/terraform-scaling-stack-segmentation-and-terragrunt-pilot.md`
- `docs/runbooks/rollback-procedure.md`

External references (checked 2026-02-23):
- Git worktree (official git docs): https://git-scm.com/docs/git-worktree
- GitLab subgroups (ownership boundaries): https://docs.gitlab.com/user/group/subgroups/
- GitLab protected environments (release approvals/gates): https://docs.gitlab.com/ci/environments/protected_environments/
- OpenTelemetry semantic conventions (HTTP spans; trace field naming inspiration): https://opentelemetry.io/docs/specs/semconv/http/http-spans/

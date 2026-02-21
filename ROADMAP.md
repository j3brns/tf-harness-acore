# AgentCore Roadmap

This document outlines planned features and improvements for the Bedrock AgentCore framework.

## ✅ Completed

- [x] **GitLab CI/CD & WIF Integration**: Secure credential-free deployments for enterprise GitLab on-prem/cloud.
- [x] **Expanded MCP Server Library**: Added S3 Tools and a Generic AWS CLI MCP server for agent orchestration.
- [x] **OIDC PKCE Support**: Hardened authorization code flow to prevent interception.
- [x] **Native 15-Minute Streaming**: Upgraded to AWS Provider v6.x to bypass the 29s REST API timeout.
- [x] **Multi-Tenant Session Partitioning**: Refactored DynamoDB to use composite keys (app_id + session_id).
- [x] **Full Tenant Isolation (Rule 14)**: Implemented cross-tenant isolation in BFF Proxy and automated isolation tests.
- [x] **OIDC Token Refresh Handler**: Implemented seamless session rotation in the Authorizer (Issue #13).
- [x] **OIDC Discovery Integration**: Automated build-time endpoint discovery via `.well-known/openid-configuration` (Issue #15).

## 🔁 Roadmap/Issue Parity Status

- Roadmap-planned work items are now mapped to GitHub issues `#17` through `#34`.
- Existing open issues currently outside this scheduled roadmap:
  - `#4` RFC: Serverless SPA & BFF Architecture (Token Handler Pattern)
  - `#10` Observability dashboards + inference-profile cost isolation
  - `#11` BFF proxy runtime invoke (duplicate candidate)
  - `#12` BFF proxy runtime invoke
  - `#16` Agent identity vs alias naming
- Backlog hygiene action: triage open duplicates (`#11`/`#12`) and close or merge completed items where applicable.

## 🚀 Near-Term Program (v0.1.x -> v0.2.0)

### Workstream A: Terraform Provider Novation (CLI -> Native)

- [ ] **A0: Resource Coverage Matrix + Freeze Point**
  * Build a source-of-truth matrix for each CLI-managed resource: `native-now`, `native-later`, `cli-required`.
  * Pin provider version and map migration candidates to exact resource names.
  * Record explicit non-goals (resources that must stay CLI for now).
  * **Issue:** #17

- [ ] **A1: Dev-Only Pilot (Lowest-Risk Family First)**
  * Start with resource families already validated as native-capable in provider docs.
  * Run parallel plan comparison (`current CLI` vs `native branch`) and capture diff expectations.
  * Require zero unplanned destroys before any apply in dev.
  * **Issue:** #18

- [ ] **A2: State Transition Runbook**
  * Define `import`/`moved` procedures per resource family and add rollback instructions.
  * Add pre-flight checks: state backup, drift check, plan delta review.
  * Add post-flight checks: idempotent second apply, smoke validation, audit trail.
  * **Issue:** #19

- [ ] **A3: Promotion Through Existing Gates**
  * Dev: `promote:dev` required before deploy.
  * Test: manual `release/*` pipeline + `promote:test` required.
  * Prod: tagged SHA with `gate:prod-from-test` evidence.
  * **Issue:** #20

- [ ] **A4: Decommission Legacy CLI Paths**
  * Remove migrated `null_resource` branches only after 2 green promotion cycles.
  * Keep CLI fallback only for matrix entries still marked `cli-required`.
  * **Issue:** #21

### Workstream B: Tag + Policy Consolidation

- [ ] **B0: Canonical Tag Taxonomy**
  * Standardize required tags across all modules: `AppID`, `Environment`, `AgentName`, `ManagedBy=Terraform`, `Owner`.
  * Ensure provider `default_tags` and module `tags` are non-conflicting and deterministic.
  * **Issue:** #22

- [ ] **B1: IAM/Cedar Policy Rationalization**
  * Consolidate duplicated IAM statements and normalize wildcard exceptions to documented AWS-required cases only.
  * Normalize Cedar policy structure, naming, and schema versioning.
  * **Issue:** #23

- [ ] **B2: ABAC Consistency Pass (Rule 14)**
  * Verify `tenant_id`/`app_id` conditions are consistently enforced in runtime, proxy, and policy layers.
  * Add policy-level negative tests for cross-tenant access attempts.
  * **Issue:** #24

- [ ] **B3: CI Enforcement**
  * Add lint/test checks for required tags and policy conformance.
  * Fail CI on missing required tags or undocumented wildcard policy actions.
  * **Issue:** #25

### Workstream C: Tenancy Portal/API Refinement

- [ ] **C0: API Contract First**
  * Define versioned tenancy admin API contract for onboarding, lifecycle, and access control.
  * Required operations: `create tenant`, `suspend tenant`, `rotate tenant credentials`, `fetch tenant audit summary`.
  * **Issue:** #26

- [ ] **C1: Authorization and Guardrails**
  * Enforce claim-based tenant authority (never trust tenant identifiers from request body alone).
  * Add policy checks that bind portal actions to `app_id` + `tenant_id` scope.
  * **Issue:** #27

- [ ] **C2: Onboarding + JIT Provisioning**
  * Implement deterministic onboarding flow for tenant prefixes, session partitions, and baseline policy attachments.
  * Add retry-safe, idempotent behavior for partial failures.
  * **Issue:** #28

- [ ] **C3: Operational UX**
  * Add tenant diagnostics endpoints (health, last deployment SHA, policy version, memory usage summary).
  * Add audit/event timeline view consumable by portal UI and API clients.
  * **Issue:** #29

## 📈 Enterprise Features (Scale & Compliance)

- [ ] **Persistence for Audit Logs (Rule 15)**
  * **Problem:** Audit logs (Shadow JSON) are currently ephemeral or stuck in CloudWatch.
  * **Solution:** Direct export of proxy interaction logs to S3 with Athena integration for long-term compliance reporting.
  * **Issue:** #30

- [ ] **Cross-Account Gateway Support**
  * **Problem:** BFF and AgentCore Gateway currently assume the same AWS account.
  * **Solution:** Enhance IAM roles and Resource-Based Policies to support cross-account tool invocation and identity propagation.
  * **Issue:** #31

- [ ] **Automated Streaming Load Tester**
  * **Problem:** Hard to verify the 15-minute "Streaming Wall" without manual testing.
  * **Solution:** A CLI utility that invokes the agent with a "long-running" mock tool to verify connectivity persistence up to 900s.
  * **Issue:** #32

## 🛠️ Developer Experience (DX)

- [ ] **Native Swagger/OpenAPI Generation**
  * **Problem:** MCP tools are defined in code but not documented for the frontend.
  * **Solution:** Automatically generate an OpenAPI spec from the MCP tools registry for use in the Web UI.
  * **Issue:** #33

- [ ] **Frontend Component Library**
  * **Problem:** Current frontend is a simple template.
  * **Solution:** Provide a library of React/Tailwind components for building specialized agent dashboards.
  * **Issue:** #34

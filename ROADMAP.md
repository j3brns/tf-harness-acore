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

- Roadmap-planned work items are now mapped to GitHub issues `#10`, `#16`, `#17`-`#34`, `#48`, `#50`-`#54`, and `#61`-`#65`.
- Existing open issues currently outside this scheduled roadmap:
  - None (all current open issues are now queue-classified; non-roadmap backlog has been triaged/closed or scheduled).
- Backlog hygiene action: maintain queue status/type labels for any newly created unscheduled issues (`triage` intake state).

## 🚀 Near-Term Program (v0.1.x -> v0.2.0)

### Workstream A: Terraform Provider Novation (CLI -> Native)

- [x] **A0: Resource Coverage Matrix + Freeze Point**
  * Build a source-of-truth matrix for each CLI-managed resource: `native-now`, `native-later`, `cli-required`.
  * Pin provider version and map migration candidates to exact resource names.
  * Record explicit non-goals (resources that must stay CLI for now).
  * **Issue:** #17

- [x] **A1: Dev-Only Pilot (Lowest-Risk Family First)**
  * Start with resource families already validated as native-capable in provider docs.
  * Run parallel plan comparison (`current CLI` vs `native branch`) and capture diff expectations.
  * Require zero unplanned destroys before any apply in dev.
  * **Issue:** #18

- [x] **A2: State Transition Runbook**
  * Define `import`/`moved` procedures per resource family and add rollback instructions.
  * Add pre-flight checks: state backup, drift check, plan delta review.
  * Add post-flight checks: idempotent second apply, smoke validation, audit trail.
  * **Issue:** #19

- [x] **A3: Promotion Through Existing Gates**
  * Dev: `promote:dev` required before deploy.
  * Test: manual `release/*` pipeline + `promote:test` required.
  * Prod: tagged SHA with `gate:prod-from-test` evidence.
  * **Issue:** #20

- [x] **A4: Decommission Legacy CLI Paths**
  * Remove migrated `null_resource` branches only after 2 green promotion cycles (default requirement; Issue #21 used a temporary documented dispensation due no active consumers at the time).
  * Keep CLI fallback only for matrix entries still marked `cli-required`.
  * **Issue:** #21

### Workstream B: Tag + Policy Consolidation

- [x] **B0: Canonical Tag Taxonomy**
  * Standardize required tags across all modules: `AppID`, `Environment`, `AgentName`, `ManagedBy=Terraform`, `Owner`.
  * Ensure provider `default_tags` and module `tags` are non-conflicting and deterministic.
  * **Issue:** #22

- [x] **B1: IAM/Cedar Policy Rationalization**
  * Consolidate duplicated IAM statements and normalize wildcard exceptions to documented AWS-required cases only.
  * Normalize Cedar policy structure, naming, and schema versioning.
  * **Issue:** #23

- [x] **B2: ABAC Consistency Pass (Rule 14)**
  * Verify `tenant_id`/`app_id` conditions are consistently enforced in runtime, proxy, and policy layers.
  * Add policy-level negative tests for cross-tenant access attempts.
  * **Issue:** #24

- [x] **B3: Policy Exception Inventory**
  * Generate and publish a canonical report of all IAM wildcard exceptions and their rationales.
  * Standardize tag conformance inventory across foundation, tools, and runtime modules.
  * **Issue:** #61

- [ ] **B4: CI Enforcement**
  * Add lint/test checks for required tags and policy conformance.
  * Fail CI on missing required tags or undocumented wildcard policy actions.
  * **Issue:** #25

- [ ] **B4: Policy Exception Inventory + Conformance Report**
  * Generate a reproducible inventory/report for approved wildcard exceptions and tag/policy conformance coverage.
  * Make policy review faster by linking exception usage to CI enforcement outputs.
  * **Issue:** #61

- [ ] **B5: Agent Identity vs Alias Naming Enforcement**
  * Enforce migration-safe `agent_name` validation to reject low-entropy/collision-prone names while aligning new deployments to ADR 0012 naming conventions.
  * Clarify and implement `AgentAlias = app_id` visibility tagging without conflicting with canonical tag behavior.
  * Update examples/docs to distinguish internal `agent_name` identity from human-facing `app_id` alias.
  * **Issue:** #16

### Workstream C: Tenancy Portal/API Refinement

- [x] **C0: API Contract First**
  * Define versioned tenancy admin API contract for onboarding, lifecycle, and access control.
  * Required operations: `create tenant`, `suspend tenant`, `rotate tenant credentials`, `fetch tenant audit summary`.
  * **Issue:** #26

- [x] **C1: Authorization and Guardrails**
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

- [x] **C4: CloudFront SPA/API Behavior Hardening**
  * Prevent SPA fallback rewrites from masking `/api/*` and `/auth/*` 4xx responses.
  * Preserve SPA deep-link behavior while keeping API/auth error semantics intact.
  * Align CloudFront caching behavior/comments for SPA assets vs `index.html`.
  * **Issue:** #48

- [ ] **C5: Portal Diagnostics + Audit Timeline UI**
  * Add portal UI views/components for tenant diagnostics and audit timeline consumption.
  * Consume the operational UX API payloads after C3 endpoint work is complete.
  * Leverage existing OpenAPI/component-library DX outputs where applicable.
  * **Issue:** #50

- [ ] **C6: Portal Session Expiry + Scope-Mismatch UX Hardening**
  * Add explicit portal UX handling for session expiry, re-auth, and tenant/app scope mismatch responses.
  * Ensure auth/API failure states are user-safe, testable, and consistent with BFF token-handler flows.
  * **Issue:** #62

## 📈 Enterprise Features (Scale & Compliance)

- [x] **Persistence for Audit Logs (Rule 15)**
  * **Problem:** Audit logs (Shadow JSON) are currently ephemeral or stuck in CloudWatch.
  * **Solution:** Direct export of proxy interaction logs to S3 with Athena integration for long-term compliance reporting.
  * **Issue:** #30

- [ ] **Cross-Account Gateway Support**
  * **Problem:** BFF and AgentCore Gateway currently assume the same AWS account.
  * **Solution:** Enhance IAM roles and Resource-Based Policies to support cross-account tool invocation and identity propagation.
  * **Issue:** #31

- [x] **Automated Streaming Load Tester**
  * **Problem:** Hard to verify the 15-minute "Streaming Wall" without manual testing.
  * **Solution:** A CLI utility that invokes the agent with a "long-running" mock tool to verify connectivity persistence up to 900s.
  * **Issue:** #32

- [ ] **Agent Observability Dashboards + Inference-Profile Cost Isolation**
  * **Problem:** Operators lack first-class per-agent dashboards and a documented, repeatable cost-isolation workflow tied to application inference profiles.
  * **Solution:** Add optional Terraform-managed CloudWatch dashboards per agent and document the per-agent inference-profile `modelId` usage pattern for cost attribution.
  * **Issue:** #10

- [ ] **CloudFront Custom Domain + ACM for BFF**
  * **Problem:** The default BFF CloudFront distribution uses the default CloudFront certificate and lacks a first-class custom-domain workflow.
  * **Solution:** Add optional alias + ACM certificate support (and document Route53/DNS requirements) while preserving default harness behavior.
  * **Issue:** #53

- [x] **CloudFront WAF Association (Optional)**
  * **Problem:** Internet-facing BFF distributions need an enterprise-ready path for WAF attachment without changing harness defaults.
  * **Solution:** Add optional CloudFront WAF association support plus documentation for managed-rule and logging considerations.
  * **Issue:** #54

- [ ] **CloudFront Access Logging for BFF (Optional)**
  * **Problem:** Enterprise operators need a first-class path for edge access logging on the BFF CloudFront distribution.
  * **Solution:** Add optional CloudFront access logging support with documentation for cost, retention, and analytics integration.
  * **Issue:** #64

- [ ] **CloudFront Cache/Origin Request Policy Standardization**
  * **Problem:** Path behavior caching/forwarding rules need a more explicit and auditable policy model.
  * **Solution:** Standardize CloudFront cache/origin request policy resources for SPA/API/auth routes while preserving current behavior.
  * **Issue:** #65

## 🛠️ Developer Experience (DX)

- [x] **Native Swagger/OpenAPI Generation**
  * **Problem:** MCP tools are defined in code but not documented for the frontend.
  * **Solution:** Automatically generate an OpenAPI spec from the MCP tools registry for use in the Web UI.
  * **Issue:** #33

- [x] **Frontend Component Library**
  * **Problem:** Current frontend is a simple template.
  * **Solution:** Provide a library of React/Tailwind components for building specialized agent dashboards.
  * **Issue:** #34

- [x] **Typed Client SDK from OpenAPI**
  * **Problem:** OpenAPI output exists, but consumers still need a stable typed client workflow to avoid ad hoc request code.
  * **Solution:** Generate and validate a typed client SDK from the OpenAPI tool spec with a documented regeneration flow.
  * **Issue:** #51

- [x] **Component Preview + Accessibility Regression Workflow**
  * **Problem:** Component library maintenance needs a repeatable preview and regression workflow.
  * **Solution:** Add a component workbench plus accessibility/regression checks for core UI components.
  * **Issue:** #52

- [ ] **OpenAPI Contract Diff/Changelog Workflow**
  * **Problem:** Teams need a fast way to review API/tool spec drift between commits/releases.
  * **Solution:** Add a reproducible contract diff summary workflow for the generated OpenAPI spec (breaking vs additive changes).
  * **Issue:** #63

# ADR 0015: BFF Identity Persistence, Interceptor Boundaries, and Multi-Tenancy Viability

## Status
Accepted

## Context

The current architecture establishes:
- Entra/OIDC-based app-facing identity and publishing patterns (ADR 0009),
- dual-registry agent discovery and workload-token A2A propagation (ADR 0010),
- a serverless SPA + BFF token-handler pattern (ADR 0011),
- canonical `AppID` / `AgentName` identity semantics (ADR 0012),
- segmented Terraform state as the target scaling direction (ADR 0013),
- and cross-plane metadata boundaries (ADR 0014).

What is still underspecified in one place is the **runtime identity persistence model** across the app-facing stack and
the **practical viability limits** for full pooled multi-tenancy at scale.

This ADR defines:
1. how identity is preserved from ingress through AgentCore and tools,
2. how inbound identity differs from outbound identity,
3. East-West partitions and CI-plane separation,
4. realistic multi-tenancy operating models,
5. scale risks and thresholds that require architecture changes.

## Decision

### 1. Identity Persistence Is Enforced via an Identity Envelope (Normative)

Identity persistence through the stack MUST be implemented using a normalized identity envelope carried across boundaries
(headers/context/session + trace metadata), not by repeatedly re-trusting raw request bodies.

Minimum envelope fields:
- `app_id`
- `tenant_id`
- `agent_name`
- principal subject (`sub` or normalized user ID)
- `session_id`
- `environment` (deployment metadata only; not a tenant auth signal)
- route/scopes/claims needed for policy decisions
- correlation IDs (`request_id`, `trace_id`)

Rules:
- `tenant_id` MUST originate from validated identity context and policy evaluation.
- `tenant_id` MUST NOT be accepted from request body/query as the sole source of truth.
- `session_id` MUST be validated against the same `app_id + tenant_id + principal` binding before downstream runtime invocation.

### 2. Inbound and Outbound Identity Are Separate Decisions (Normative)

#### Inbound Identity
Answers: **Who is calling in, and may they invoke this route/tool/runtime?**

Examples:
- API Gateway request authorizer / JWT validation for BFF routes
- AgentCore Gateway inbound auth
- AgentCore Runtime inbound auth

Inbound validation MUST:
- validate issuer/audience/scope (or IAM principal),
- normalize claims into the identity envelope,
- enforce route/tool scope checks before side effects,
- deny anonymous/no-auth paths by default unless explicitly approved and documented.

#### Outbound Identity
Answers: **Which credential/authorization mode is used when the platform calls downstream systems?**

Examples:
- BFF proxy -> AgentCore Runtime (delegated user context + workload identity pattern)
- AgentCore Gateway -> Lambda/OpenAPI/MCP targets
- AgentCore Identity credential provider access

Outbound authorization MUST:
- explicitly choose an auth mode per target (IAM SigV4 / OAuth / API key),
- preserve whether the call is user-delegated vs workload-only,
- scope credentials to target and operation where possible,
- log authorization mode and target type for auditability.

Rule:
- Valid inbound identity does **not** imply unrestricted outbound access.

### 3. East-West Partitions (Normative)

North-South ingress (browser/client to BFF/API) is distinct from East-West control boundaries.

Required partitions:
1. **CI/Release Plane**
   - Actors: GitLab CI pipeline, release approvers (CI-only personas)
   - Responsibility: build/deploy/promotion evidence, `Environment` progression
   - MUST NOT act as runtime tenant authority

2. **Identity/Control Plane**
   - Actors: Entra ID (proof-point IdP), AgentCore Identity, token broker
   - Responsibility: authn, token validation/exchange, credential-provider configuration

3. **Application Control Plane**
   - Actors: API Gateway, BFF Lambdas (auth handler, authorizer, proxy)
   - Responsibility: route authz, session binding, request shaping, identity normalization

4. **Agent Runtime / Tool Control Plane**
   - Actors: AgentCore Gateway, AgentCore Runtime, policy/evaluator systems
   - Responsibility: runtime invocation authz, tool ingress/egress authz, policy enforcement

5. **Runtime Data Plane**
   - Actors: DynamoDB session store, S3 memory/data prefixes, audit sinks
   - Responsibility: tenant-partitioned persistence and auditable access

6. **Observability / Audit Plane** (cross-cutting)
   - Responsibility: correlated logs, traces, metrics, audit records
   - MUST preserve identity correlations without storing secrets

### 4. Interceptor Boundaries (Normative)

Interceptors may be authorizers, middleware, handlers, wrappers, or policy hooks. They are mandatory enforcement
points at identity-sensitive boundaries.

#### Inbound Interceptor Chain (BFF stack)
1. **Route Auth Interceptor (API Gateway/BFF ingress)**
   - Validate JWT/IAM auth, issuer/audience/scope
2. **Identity Normalization Interceptor**
   - Normalize Entra/OIDC claims into internal identity envelope
3. **Session Binding Interceptor**
   - Validate session cookie/session record and bind to `app_id + tenant_id + principal`
4. **Tenant Authorization Interceptor**
   - Apply ABAC/policy using validated identity envelope
5. **Request Validation Interceptor**
   - Enforce schema/identifier validation and block tenant override attempts

#### Outbound Interceptor Chain (BFF -> AgentCore -> tools)
1. **Delegation Context Interceptor**
   - Classify call as user-delegated, workload-only, or mixed
2. **Workload Identity / Token Exchange Interceptor**
   - Acquire scoped workload token/credentials where required
3. **Outbound Auth Selection Interceptor**
   - Select per-target auth mode (IAM/OAuth/API key)
4. **Egress Policy / Target Scope Interceptor**
   - Restrict target set and tenant-sensitive operations
5. **Audit/Trace Propagation Interceptor**
   - Propagate correlation metadata (non-secret) and record target auth mode

### 5. Multi-Tenancy Viability Model (Realistic, Normative)

Full pooled multi-tenancy is not a single binary design. The platform adopts a **tiered viability model**:

#### Tier A: Shared App/Agent Stack, Tenant-Partitioned Data (Default / Viable)
- Shared BFF/API Gateway/Lambda resources per `AppID + AgentName + Environment`
- Tenant isolation enforced via:
  - validated identity context,
  - session binding,
  - ABAC/policy checks,
  - `AppID + TenantID` data partitioning
- Recommended for most tenants and early scale

#### Tier B: Shared Control Plane, Tenant-Dedicated Data Stores (Selective)
- Shared BFF/runtime stack, but dedicated S3 prefixes/buckets or separate DDB tables for specific tenants
- Used for higher isolation/compliance/cost-accounting needs

#### Tier C: Tenant-Dedicated Runtime Stack (Exception / Premium)
- Separate `AppID/AgentName` stack or dedicated runtime deployment per tenant
- Use only when required by compliance, hard isolation, or extreme workload variance
- Higher cost and operational overhead

Rule:
- Do not claim “full multi-tenancy” for Tier A unless tenant isolation is proven in authz, session binding, storage
  partitioning, and audit traces. Shared infrastructure alone is not proof of safe multitenancy.

### 6. Scaling Parameters and Risks (Normative Planning Inputs)

This section records key scaling constraints that drive architecture decisions. Values are AWS-service-quota dependent
and MUST be checked in the target account/region during planning and before high-scale rollout.

#### 6.1 Terraform State Topology Risk: State Monolith (High Risk)

A single environment-level state key (for example `agentcore/<env>/terraform.tfstate`) creates:
- lock contention across unrelated agents/stacks,
- large plan/apply blast radius,
- increased merge contention and rollout coupling,
- harder rollback and review scope.

Target pattern (ADR 0013):
- `agentcore/<env>/<app_id>/<agent_name>/terraform.tfstate`

Rule:
- Environment-only monolithic state is acceptable only as a temporary migration baseline, not the long-term scaling model.

#### 6.2 API Gateway Scaling/Quota Considerations (BFF ingress)

As of AWS docs checked 2026-02-23 (see References), API Gateway has account/region and API-level quotas (RPS,
resources/routes, integrations, authorizers, headers/payload sizes, integration timeouts).

Implications:
- Keep BFF route surface compact and proxy where appropriate.
- Reuse authorizer patterns instead of proliferating per-route authorizers.
- Track long-running streaming timeout requirements (already using 900s for chat proxy).
- Monitor account-level throttle usage before scaling tenant traffic aggressively.

#### 6.3 Cloud Map Discovery Scaling (East-West agent mesh)

Cloud Map discovery introduces service and API throttling limits.
AWS docs (checked 2026-02-23) document default quotas including:
- `DiscoverInstances` steady rate and burst rate limits,
- instances per service,
- instances per namespace.

Implications:
- Use caching and backoff for discovery clients.
- Avoid per-request cold discovery where stable caching is possible.
- Segment namespaces/services if agent mesh grows beyond per-service/per-namespace quotas.

#### 6.4 DynamoDB Multi-Tenant Partitioning Risk

DynamoDB supports multi-tenant partitioning patterns, but hot-tenant/hot-partition issues remain possible.

Implications:
- Start with tenant-scoped PK patterns (`AppID + TenantID`) and explicit access patterns.
- Add write sharding / secondary partitioning only when traffic proves it necessary.
- Test tenant isolation and throttling behavior with representative traffic before declaring pooled scale readiness.

#### 6.5 Observability Cardinality Risk (Tenant dashboards)

Per-tenant CloudWatch metrics/dimensions at large scale can create cost and operability issues.

Implications:
- Use CloudWatch/X-Ray for per-agent operational health.
- Use Athena/Glue/BI over structured audit logs for tenant-level analytics and dashboards.
- Keep field names stable (`app_id`, `tenant_id`, `session_id`, `outcome`, `duration_ms`).

### 7. GitLab Groups and Team Release Autonomy (Normative Operating Pattern)

GitLab group structure SHOULD provide team autonomy without collapsing platform controls:

#### Platform Group (Shared Controls)
- Owns CI templates, runners, OIDC trust baseline, protected environments/tags, promotion policies
- Reviews shared-surface changes (state topology, release gates, templates)

#### Team Subgroups / Projects (Delivery Autonomy)
- Own app/agent repos and day-to-day merge cadence
- Can self-serve `dev` and (optionally) `test` within policy
- Must provide promotion evidence for higher environments

#### Production Promotion
- Uses protected environments/tags and explicit approvals
- Approval is a CI/release-plane action; it MUST NOT modify runtime tenant authorization logic

Metadata alignment (with ADR 0014):
- Mirror `GitLabGroup`, `GitLabProject`, `ReleaseChannel`, `Owner` into resource tags where applicable
- Record pipeline/approval lineage in release evidence, not runtime auth context

### 8. Local Development / Inner Loop Support (Normative)

The architecture MUST support a fast inner loop without cloud round-trips for every identity/tenant change.

Required local-dev capabilities:
- mock OIDC/JWT claim fixtures (including tenant/app claims)
- identity-envelope normalization tests
- session-binding tests
- interceptor unit tests (inbound and outbound)
- replayable structured audit log samples for dashboard/query development
- local MCP tool testing and request replay where possible

Rule:
- A developer SHOULD be able to validate identity propagation, tenant isolation logic, and metadata fields locally
  before GitLab deployment/promotion.

## Consequences

### Positive
- Clear identity persistence and interceptor contract across BFF -> AgentCore -> tools
- Realistic multi-tenancy posture (tiered, not hand-wavy “fully multi-tenant” claims)
- Better scaling planning with explicit quota/risk touchpoints
- Cleaner separation of release autonomy from runtime authorization
- Stronger local-dev parity for identity and observability

### Tradeoffs
- More upfront architecture and test discipline
- Additional interceptor code and trace/log field conventions
- More explicit planning work for quota validation and state segmentation before high-scale rollout

## References

Repo references:
- `docs/adr/0009-strands-agent-publishing.md`
- `docs/adr/0010-service-discovery.md`
- `docs/adr/0011-serverless-spa-bff.md`
- `docs/adr/0012-agent-identity-alias.md`
- `docs/adr/0013-segmented-state-key-strategy.md`
- `docs/adr/0014-metadata-tagging-telemetry-and-release-metadata-boundaries.md`
- `docs/architecture.md`
- `terraform/modules/agentcore-bff/apigateway.tf`
- `terraform/modules/agentcore-bff/audit_logs.tf`
- `terraform/modules/agentcore-foundation/inference_profile.tf`
- `terraform/modules/agentcore-foundation/observability.tf`

AWS sources (AWS Knowledge MCP-backed, checked 2026-02-23):
- API Gateway quotas (general): https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html
- API Gateway REST API quotas/config/runtime limits: https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html
- AWS Cloud Map quotas: https://docs.aws.amazon.com/cloud-map/latest/dg/cloud-map-limits.html
- AWS Cloud Map throttling guidance (`DiscoverInstances`): https://docs.aws.amazon.com/cloud-map/latest/dg/throttling.html
- DynamoDB data modeling building blocks (multi-tenancy, TTL, write sharding): https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/data-modeling-blocks.html
- Bedrock AgentCore inbound JWT authorizer: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html
- Bedrock AgentCore gateway inbound auth: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-inbound-auth.html
- Bedrock inference profiles: https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html

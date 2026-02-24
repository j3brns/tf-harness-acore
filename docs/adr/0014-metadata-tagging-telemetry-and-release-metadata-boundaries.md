# ADR 0014: Metadata Boundaries (Resource Tags, Tenant Telemetry, Traces, and Release Metadata)

## Status
Accepted

## Context

The platform needs a consistent metadata model across four different concerns:

1. **Infrastructure inventory and governance** (AWS resource ownership, environment, cost center).
2. **Tenant isolation and request auditing** (per-request `app_id`, `tenant_id`, `session_id` attribution).
3. **Observability** (logs, tracing, dashboards, incident response).
4. **Release autonomy** (GitLab group/project ownership, environment promotion evidence, approvals).

A recurring simplification request is "everything should be tagged." That principle is directionally correct, but AWS
resource tags are not sufficient for all metadata classes:

- Shared resources (API Gateway, Lambda, DynamoDB tables, CloudFront) are **not tenant-specific** and must not be
  assigned a single `TenantID` resource tag.
- Tenant identity is **request/session metadata**, not a long-lived infrastructure identity.
- CI/promotion data belongs to the **release plane**, not the runtime plane.

We need a canonical rule that defines what is tagged at the AWS resource layer vs what is recorded in logs, traces,
audit records, and CI/release metadata.

This ADR extends the canonical tag taxonomy in `docs/architecture.md` and aligns with:
- ADR 0009 (Strands publishing, Entra identity, release stages)
- ADR 0010 (service discovery and workload-token-based A2A)
- ADR 0011 (serverless SPA/BFF token handler)
- ADR 0012 (agent identity vs alias naming)
- ADR 0013 (segmented state key strategy)

## Decision

### 1. Metadata MUST Be Modeled by Plane (Not Forced Into AWS Resource Tags)

We define four metadata planes:

1. **Infrastructure Plane (AWS Resource Tags)**  
   Long-lived metadata on provisioned AWS resources.
2. **Runtime Request Plane (Structured Logs / Audit Records)**  
   Per-request and per-session identity + outcome metadata.
3. **Tracing Plane (X-Ray annotations/metadata)**  
   Correlation and queryable execution metadata across components.
4. **Release Plane (GitLab/Git metadata + promotion evidence)**  
   CI/CD ownership, approvals, pipeline evidence, and environment promotion lineage.

Rule:
- All relevant artifacts MUST carry metadata.
- Metadata MUST be recorded in the correct plane.
- Tenant/request metadata MUST NOT be represented solely as AWS resource tags on shared resources.

### 2. Infrastructure Plane: Canonical AWS Resource Tags (Required)

All AWS resources managed by Terraform MUST carry the canonical tags already enforced by provider `default_tags` and
`local.canonical_tags`, and SHOULD include additional governance/cost tags where applicable.

#### Required Canonical Tags (existing baseline)
- `AppID`
- `AgentAlias`
- `Environment`
- `AgentName`
- `ManagedBy`
- `Owner`

#### Recommended Extended Tags (new standard)
These SHOULD be added to shared module inputs and propagated where known:
- `CostCenter`
- `BusinessUnit`
- `ServiceBoundary` (`foundation|tools|runtime|governance|bff`)
- `WorkloadType` (`agent-runtime|bff|tool|governance|observability`)
- `Repo`
- `GitLabGroup`
- `GitLabProject`
- `ReleaseChannel` (`dev|test|prod`)
- `ManagedByTeam`

Rules:
- Canonical keys remain immutable at the root module (user tags cannot override canonical values).
- Extended tags MAY be supplied via `var.tags` until dedicated variables are introduced.
- Shared resources MUST NOT be tagged with a single `TenantID` unless the resource itself is tenant-dedicated.

### 3. Runtime Request Plane: Tenant and Session Metadata (Required)

Tenant and request identity metadata MUST be captured in structured logs and audit records, not only inferred from
resource tags.

Required request-plane fields (minimum):
- `app_id`
- `tenant_id`
- `agent_name`
- `environment`
- `session_id` (or requested/authorized/runtime variants)
- `request_id`
- `route` / `resource_path`
- `status_code`
- `outcome`
- `duration_ms`

Implementation guidance:
- API Gateway access logs SHOULD include `app_id` and `tenant_id` from authorizer context.
- The BFF proxy SHOULD emit audit shadow JSON with request/response summaries and tenant/session correlation.
- Tenant identity MUST be derived from validated authorizer/OIDC context, not untrusted request body fields.

### 4. Tracing Plane: Correlation Metadata (Required)

Tracing metadata MUST preserve identity and execution correlation across:
- BFF authorizer / auth handler
- BFF proxy
- AgentCore Gateway / Runtime interactions
- Lambda tools and downstream integrations

#### X-Ray Annotation Standard (queryable)
Use annotations for high-value indexed fields:
- `app_id`
- `tenant_id`
- `agent_name`
- `environment`
- `session_id`
- `route`
- `component`

#### X-Ray Metadata Standard (non-indexed)
Use metadata for larger diagnostic payloads:
- normalized claims summary
- downstream request envelopes
- retry diagnostics
- truncated payload previews

Rule:
- Trace annotations MUST NOT contain raw access tokens, refresh tokens, client secrets, or unredacted PII.

### 5. Cost Management and Authorization: Application Inference Profiles (Required Pattern)

Application Inference Profiles are the primary Bedrock model-invocation boundary for:
- authorization scoping (IAM policy to customer-owned profile ARN),
- app/agent-level cost allocation,
- quota management at the application boundary.

Rules:
- When Bedrock usage/cost attribution is required for an agent, `enable_inference_profile=true` SHOULD be enabled.
- Model invocations SHOULD use the application inference profile ARN/ID instead of direct foundation model IDs when the
  runtime path supports it.
- Inference profiles MUST carry canonical tags and SHOULD include extended cost tags (for example `CostCenter`).

Tenant-level cost allocation:
- `TenantID` chargeback/reporting MUST be derived from request-plane telemetry + usage attribution joins.
- Do not treat AWS resource tags as the tenant cost ledger for shared runtime infrastructure.

### 6. Tenant Dashboards and Partitioned Observability (Required Design Direction)

The platform MUST support two dashboard classes:

1. **Operational dashboards (per-agent/per-environment)**  
   CloudWatch/X-Ray dashboards and alarms for SRE/ops.
2. **Tenant-partition dashboards (analytics/audit)**  
   Athena/Glue/BI dashboards (or equivalent) over audit logs partitioned/joined by `app_id` + `tenant_id`.

Rules:
- CloudWatch dashboards SHOULD remain focused on service health and operational hot paths.
- High-cardinality tenant views SHOULD be implemented through query/analytics layers (Athena/BI), not per-tenant
  CloudWatch metric dimensions at scale.
- Tenant dashboards MUST use validated identity-derived fields (`app_id`, `tenant_id`) from audit logs.

### 7. Release Plane: GitLab Group/Project Metadata for Team Autonomy (Required Pattern)

Release autonomy is a release-plane concern and MUST be modeled separately from runtime tenant authorization.

#### Plane Separation
- **CI/Release personas** (pipeline jobs, release approvers) manage `Environment` promotion and deployment evidence.
- **Runtime personas/services** manage `TenantID` authorization and request processing.
- CI/release metadata MUST NOT be used as a substitute for runtime tenant authorization.

#### GitLab Group / Project Metadata (recommended)
GitLab group/project/environment metadata SHOULD provide:
- ownership (`OWNING_TEAM`, `GitLabGroup`, `GitLabProject`)
- release channel / environment (`dev`, `test`, `prod`)
- approval policy linkage
- promotion lineage (`promoted_from_sha`, pipeline ID, approver)

These values SHOULD be mirrored into Terraform/AWS resource tags where applicable (infrastructure plane) and into
release evidence records (release plane), but MUST remain distinct from tenant runtime metadata.

### 8. Local Development and Inner Loop Parity (Required)

Local development MUST preserve the metadata contract so developers can validate behavior before cloud deployment.

Required local-dev support patterns:
- mock identity envelopes with `app_id`, `tenant_id`, `agent_name`, `session_id`
- structured log fixtures using production field names
- interceptor/unit tests for inbound and outbound identity/tracing propagation
- replayable audit samples for dashboard/query development

Rule:
- Inner-loop validation SHOULD verify identity propagation and metadata integrity without requiring a full GitLab
  deployment cycle.

## Consequences

### Positive
- Clear separation of infrastructure ownership tags vs tenant/runtime metadata.
- Better tenant isolation posture (no accidental trust in CI or resource tags for tenant identity).
- More accurate cost allocation strategy using inference profiles + telemetry joins.
- Better release autonomy for developer teams using GitLab groups/projects without compromising runtime authz.
- Improved local-dev fidelity for observability and identity propagation testing.

### Negative
- More metadata surfaces to maintain (tags, logs, traces, CI evidence).
- Requires discipline in interceptor/logging implementations to keep field names consistent.
- Tenant cost reporting requires analytics joins rather than a single AWS cost tag dimension.

## References

Repo references:
- `docs/architecture.md` (canonical tag taxonomy + architecture overview)
- `docs/adr/0009-strands-agent-publishing.md`
- `docs/adr/0010-service-discovery.md`
- `docs/adr/0011-serverless-spa-bff.md`
- `docs/adr/0012-agent-identity-alias.md`
- `docs/adr/0013-segmented-state-key-strategy.md`
- `terraform/versions.tf` (provider `default_tags`)
- `terraform/locals.tf` (`local.canonical_tags`)
- `terraform/modules/agentcore-bff/apigateway.tf` (access log fields)
- `terraform/modules/agentcore-bff/audit_logs.tf` (Athena/Glue audit schema)
- `terraform/modules/agentcore-foundation/inference_profile.tf`
- `terraform/modules/agentcore-foundation/observability.tf`

AWS sources (AWS Knowledge MCP-backed, check date: 2026-02-23):
- Bedrock inference profiles (application inference profiles and cost/usage tracking):  
  https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html
- Create application inference profile:  
  https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-create.html
- Bedrock AgentCore inbound JWT authorizer (OIDC/JWT validation):  
  https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html
- Bedrock AgentCore gateway inbound auth (JWT/IAM/no-auth options):  
  https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-inbound-auth.html

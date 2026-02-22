# E8A AgentCore Multi-Tenancy + Routing Synthesis (Issue #73)

Checked on: 2026-02-22

## Why This Exists (Repo Relevance)

Issue `#73` (E8A) required a segmented Terraform state-key strategy and a migration-safe CI handoff. During review, a key design question surfaced:

- Should backend state partitioning key on `tenant_id`, `app_id`, or `agent_name`?
- Where is the join between API path, agent endpoint, and runtime ARN?
- How should this align with AWS multi-tenant guidance and AgentCore Gateway interceptors?

This synthesis captures the repo-specific model that best aligns with AWS guidance and the current implementation.

## Scope of This Synthesis

In scope:
- Multi-tenant identity/authorization concepts relevant to AgentCore Runtime/Gateway
- Route-to-runtime binding model (API path -> agent target -> runtime ARN)
- Implications for Terraform backend state partitioning
- Alignment with AWS Prescriptive Guidance and AgentCore Gateway interceptors

Out of scope:
- Changing the current BFF proxy to dynamic route resolution (future work)
- Tenant-dedicated infrastructure rollout design (future optional pattern)
- CI implementation details for E8B (`#74`) beyond the ADR handoff contract

## AWS Sources Reviewed (AWS Knowledge MCP-backed)

### AgentCore Docs

- Inbound JWT authorizer (Runtime/Gateway claim validation):
  - https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/inbound-jwt-authorizer.html
- Scope credential-provider access by workload identity:
  - https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/scope-credential-provider-access.html
- Gateway permissions prerequisites:
  - https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-prerequisites-permissions.html

### AgentCore / AWS Blog (implementation patterns)

- Gateway interceptors and fine-grained access control / tenant isolation / header propagation:
  - https://aws.amazon.com/blogs/machine-learning/apply-fine-grained-access-control-with-bedrock-agentcore-gateway-interceptors/

### AWS Prescriptive Guidance (agentic multi-tenancy)

- Agents meet multi-tenancy:
  - https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-multitenant/agents-meet-multi-tenancy.html
- Enforcing tenant isolation:
  - https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-multitenant/enforcing-tenant-isolation.html
- Focus area 3: Architect for multi-tenancy and control:
  - https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-operationalizing-agentic-ai/focus-areas-multitenancy.html

## Repo Ground Truth (Current Implementation)

### Current Join Path (Static Binding)

In the current repo, `POST /api/chat` is statically bound to one proxy Lambda, and that proxy Lambda is configured with one `AGENTCORE_RUNTIME_ARN` per deployment.

Relevant code paths:
- API route -> proxy function URL:
  - `terraform/modules/agentcore-bff/apigateway.tf`
- Proxy Lambda env vars (`AGENTCORE_RUNTIME_ARN`, `AGENTCORE_REGION`):
  - `terraform/modules/agentcore-bff/lambda.tf`
- Root-module wiring (`module.agentcore_runtime.runtime_arn` -> BFF input):
  - `terraform/main.tf`
- Runtime invoke URL construction from ARN + region:
  - `terraform/modules/agentcore-bff/src/proxy.js`

Important distinction:
- `app_id` and `tenant_id` are forwarded as headers / context (`x-app-id`, `x-tenant-id`) for tenancy/isolation and audit behavior.
- They do **not** currently select the runtime ARN.

### Practical Consequence

Today the runtime target selection model is:

```text
POST /api/chat -> BFF Proxy -> (single configured runtime_arn)
```

There is no dynamic route/app/agent registry in the current BFF path.

## Synthesis: Identity, Routing, and State Partitioning Are Different Joins

The most important alignment point is to avoid conflating three separate concerns:

1. **Inventory / deployment partitioning** (Terraform state, asset grouping)
2. **Runtime target routing** (which agent/runtime handles the request)
3. **Tenant authorization context** (who is allowed to access data/tools)

### Recommended Repo Model (Aligned)

#### `app_id` = Inventory / Taxonomy Partition (Primary)

Use `app_id` as the primary application partition:
- It represents the atomic collection of services in an app.
- It is stable enough for naming and inventory purposes.
- It maps well to operator mental models and instance naming schemes.

This is the right default anchor for Terraform backend state segmentation.

#### `agent_name` = Physical Runtime Identity (Discriminator)

Use `agent_name` to disambiguate multiple physical agents under one app:
- immutable internal identity
- physical runtime binding handle
- directly associated with a specific AgentCore runtime ARN

This is the right suffix in backend state keys when multiple independently managed agents exist under one `app_id`.

#### `tenant_id` = Authorization / Isolation Context (Usually Not the Default State Key)

Use `tenant_id` primarily for:
- request authorization and isolation
- data partitioning / ABAC
- policy/interceptor decisions
- audit context propagation

Do **not** make `tenant_id` the default backend key segment unless you are actually deploying tenant-dedicated infrastructure/stacks.

### Why This Aligns with AWS Guidance

AWS Prescriptive Guidance emphasizes tenant context propagation and isolation policies across agent interactions, tools, and data access. It does not require tenant ID to be the infrastructure state partition key for all stacks.

The Gateway interceptors guidance is also consistent with this split:
- tenant ID and user ID should be passed and validated for multi-tenant tool access,
- authorization/filtering is enforced at request/response interception points,
- identity context propagation and act-on-behalf token scoping are runtime security controls.

That is a **runtime authorization boundary**, not automatically a Terraform state namespace boundary.

## Explicit Join Model (Recommended)

### 1. Routing Join (Path -> Agent -> Runtime)

Use an explicit routing/binding model:

```text
API path -> route binding -> agent_name -> runtime_arn -> AgentCore endpoint
```

This keeps runtime target selection explicit and auditable.

### 2. Tenancy Join (Caller -> Allowed Scope)

Use tenant context for authorization and policy enforcement:

```text
caller JWT / session -> tenant_id (+ user_id, claims, scopes) -> allowed app/tool/resource actions
```

This is where JWT authorizers, workload identities, IAM scoping, AgentCore Policy, and Gateway interceptors fit.

### 3. State Join (Deploy Unit -> Backend Key)

Use deploy-unit identity for Terraform state:

```text
env + app_id (+ agent_name when independently deployed) -> backend key
```

This is what ADR 0013 is deciding.

## State Key Guidance (Repo-Consistent)

### Default Patterns

- App-level stack:
  - `agentcore/{env}/{app_id}/terraform.tfstate`
- Agent-level stack:
  - `agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate`

### Tenant-Dedicated Infra (Optional Pattern)

If a future design introduces tenant-dedicated stacks, add a tenant alias only there:

- `agentcore/{env}/{app_id}/tenants/{tenant_alias}/terraform.tfstate`

Use `tenant_alias` (not raw `tenant_id`) if:
- tenant identifiers are sensitive,
- the org wants a stable infra namespace decoupled from domain identifiers,
- migration/rename semantics need explicit control.

This alias behaves like a small registry/mapping (`tenant_id -> tenant_alias`) if it is not purely deterministic.

## Alignment with AgentCore Gateway Interceptors (Deep Fit)

The AgentCore Gateway interceptors model is highly compatible with the repo's Rule 14 tenancy posture:

- **Gateway request interceptor** is the right place for:
  - tenant/user claim extraction and validation
  - scope checks for tool invocation
  - header propagation / context normalization
  - data sanitization and request transformation
- **Gateway response interceptor** is the right place for:
  - tool discovery filtering (tenant/workspace/role aware)
  - response redaction
  - audit enrichment / observability metadata

For this repo, that suggests:
- keep Terraform state partitioning keyed to deploy units (`app_id`, `agent_name`),
- keep tenant enforcement in runtime/Gateway policy and interceptor layers,
- only introduce tenant-specific state partitions when infrastructure itself is tenant-dedicated.

## Implications for E8A / E8B

### For E8A (Issue #73)

- Supports using `app_id` as the primary state partition anchor.
- Supports `agent_name` as the discriminator for independently managed agent stacks.
- Argues against defaulting backend keys to `tenant_id`.

### For E8B (Issue #74)

- Backend key derivation should remain a deploy-time CI concern.
- Do not derive state keys from request-time JWT claims.
- If future routing becomes dynamic, add an explicit route-binding registry rather than encoding routing semantics into backend state keys.

## Inference vs Confirmed Facts

Directly confirmed from AWS docs/blog:
- JWT authorizer supports audiences/clients/scopes/custom claims for Runtime/Gateway
- workload identity-based scoping for credential providers
- Gateway interceptors support request/response transformations, fine-grained access control, tenant isolation, header propagation
- Prescriptive Guidance emphasizes tenant context propagation and isolation controls in multi-tenant agent architectures

Inference (repo design synthesis):
- `app_id` should be the default inventory/state partition anchor
- `tenant_id` should usually remain an authorization context, not a default state-key segment
- explicit route binding should be modeled separately from tenancy and backend state naming

# Bedrock AgentCore Multi-Tenancy Architecture

## Document Status
| Aspect | Status |
|--------|--------|
| **Version** | 1.0.0 |
| **Status** | **Approved** |
| **Context** | North-South Hierarchical Join |

---

## 1. Core Model: The North-South Join

The architecture uses a hierarchical identity model that anchors tenancy between the **Application Context (North)** and the **Infrastructure Implementation (South)**.

### 1.1 The Hierarchy
*   **North (App ID)**: The logical application container. This defines the "Fast Loading Dev" context or the Production application boundary.
*   **Middle (Tenant ID)**: The organizational slice. This is the unit of data ownership and isolation.
*   **South (Agent Name)**: The physical AI resource (Bedrock Agent). This is the shared compute engine.

### 1.2 The "Join" Logic
All state and access control are anchored by the **Composite Key**:

```text
Identity = [App ID] + [Tenant ID]
Resource = [Agent Name]
```

This ensures that:
1.  **Dev/Prod Parity**: Changing `App ID` fully isolates development data from production data, even on the same Agent.
2.  **Infrastructure Efficiency**: A single "South" Agent resource serves multiple "North" Apps and Tenants (Shared Compute).

---

## 2. Tenant Isolation Strategy

### 2.1 Identity-Based Isolation (Logical)
*   **Mechanism**: Attribute-Based Access Control (ABAC).
*   **Enforcement**: The **BFF Proxy** validates every request. It ensures `session.tenant_id == token.tenant_id` before invoking the runtime.
*   **Propagation**: The `x-tenant-id` and `x-app-id` headers are injected into every downstream request.

### 2.2 Physical Isolation (Credential-Level)
*   **Mechanism**: **Dynamic IAM Session Policies**.
*   **Enforcement**: The BFF Proxy calls `sts:AssumeRole` for the Agent Runtime role for *every* request.
*   **Scope**: A dynamic policy is generated that restricts the agent's credentials strictly to the tenant's prefix: `s3://bucket/{app_id}/{tenant_id}/*`.
*   **Outcome**: Even if the agent is compromised via prompt injection, it physically cannot access other tenants' data.

### 2.3 Partitioned Persistence

### 2.3 Compute Isolation (Shared)
*   **Runtime**: Shared Lambda function. Isolation is enforcing by the Context Object passed to the handler.
*   **Bedrock Agent**: Shared Resource. The Agent's "Knowledge Base" queries are filtered by metadata tags corresponding to the Tenant ID.

---

## 3. Data Partitioning & Residency

### 3.1 Data Partitioning Methods
| Store | Partition Strategy | Key Structure |
|-------|-------------------|---------------|
| **DynamoDB** | **Table Partitioning** | PK: `APP#{appid}#TENANT#{tid}` |
| **S3** | **Prefix Isolation** | `/{appid}/{tid}/` |
| **CloudWatch** | **Log Streams** | `/aws/lambda/proxy/{tid}/{session_id}` |
| **Vector DB** | **Metadata Filtering** | Filter: `metadata.tenant_id == {tid}` |

### 3.2 Data Residency
*   **Regional Enforcement**: The `app_id` is bound to a specific AWS Region.
*   **Compliance**: All persistent storage for a tenant remains within the region defined by their App's deployment.

---

## 4. API Gateway & Ingress

### 4.1 Integration
*   **Entry Point**: Regional API Gateway acting as the **Northbound** anchor.
*   **Route Handling**: `/{app_id}/api/v1/agent/{agent_name}/chat`.
*   **Host Resolution**: Support for custom domains mapping to specific `app_ids` (e.g., `dev.myapp.com` -> `app_id=dev`).

### 4.2 Ingress/Egress Controls
*   **Ingress**: WAF rules applied per API Gateway Stage. Rate limiting via Usage Plans linked to `tenant_id` API Keys.
*   **Egress**: VPC Endpoints for S3/DynamoDB. Internet access via NAT Gateway with strict Security Group rules for the Proxy Lambda.

---

## 5. Identity & Access Control

### 5.1 Identity Provider Linkage
*   **OIDC Integration**: Tenants act as OIDC Issuers (e.g., Entra ID, Okta).
*   **Claim Mapping**:
    *   `iss` -> Trusted Issuer Registry.
    *   `tid` (or custom claim) -> **Tenant ID**.
    *   `aud` -> **App ID**.

### 5.2 Cross-Tenant Access
*   **Default**: **DENY ALL**.
*   **Exception**: "System" or "Admin" tenants defined in a specific policy override table.
*   **Enforcement**: Cedar Policies evaluated at the Proxy layer.

---

## 6. Service Discovery & Deployment

### 6.1 Service Discovery
*   **Mechanism**: AWS Cloud Map (East-West) for Agent-to-Agent communication.
*   **Attributes**: Instances registered with `app_id` and `tenant_id` metadata.
*   **Lookup**: `DiscoverInstances(ServiceName, Filter={tenant_id})`.

### 6.2 Deployment Unit
*   **Unit**: The **Agent Module** (Terraform).
*   **Scope**: Deploys the "South" infrastructure (Runtime, Bedrock Agent).
*   **Updates**: Zero-downtime updates via Lambda Aliases and Traffic Shifting.

---

## 7. Scaling & Resource Allocation

### 7.1 Scaling Strategy
*   **Serverless**: Relies on Lambda and DynamoDB on-demand scaling.
*   **Concurrency**: Provisioned Concurrency settings managed per `app_id` tier (e.g., Prod gets reserved capacity, Dev gets standard).

### 7.2 Resource Allocation Policies
*   **Quotas**: Enforced by the Proxy before execution.
    *   Max Tokens / Minute.
    *   Max Concurrent Sessions.
*   **Priority**: "Gold" tenants (metadata flag) get priority processing via dedicated SQS queues (future enhancement).

---

## 8. Monitoring, Logging & Audit

### 8.1 Monitoring
*   **Metrics**: CloudWatch custom metrics dimensioned by `TenantID`.
    *   `Latency`, `ErrorRate`, `TokenUsage`.
*   **Dashboards**: Automated dashboards generated per `AppID`.

### 8.2 Logging & Audit Trails
*   **Access Logs**: API Gateway logs with `context.authorizer.tenant_id`.
*   **Application Logs**: Structured JSON logs including `{"tenant_id": "...", "app_id": "..."}`.
*   **Audit**: All "Write" operations (Memory/State) generate a CloudTrail-like event sent to a dedicated Audit S3 Bucket.

---

## 9. Lifecycle Management

### 9.1 Tenant Onboarding
*   **Type**: **Zero-Touch (Just-in-Time)**.
*   **Trigger**: First successful OIDC Login.
*   **Action**: System auto-creates S3 prefixes and DynamoDB session metadata.

### 9.2 Tenant Deprovisioning
*   **Soft Delete**: Mark tenant as `inactive` in Registry.
*   **Hard Delete**: Async job (Step Function) that:
    1.  Deletes DynamoDB Session Items (Query by PK).
    2.  Empty & Delete S3 Prefix `/{app_id}/{tenant_id}/`.
    3.  Purges Vector DB entries.

### 9.3 Backup & Disaster Recovery
*   **Backup**: AWS Backup (Point-in-Time Recovery) for DynamoDB and S3.
*   **RPO/RTO**: Standard AWS Serverless guarantees.
*   **Disaster Avoidance**: Multi-AZ architecture (standard for Lambda/DynamoDB).

---

## 10. Security & Compliance

### 10.1 Key Management
*   **KMS**: AWS Managed Keys (SSE-S3) by default.
*   **CMK Option**: Support for Customer Managed Keys (CMK) per `AppID` for higher compliance requirements.

### 10.2 Secret Management
*   **Secrets Manager**: Stores OIDC Client Secrets.
*   **Access**: Roles scoped to allow reading only the specific secret for the configured `AppID`.

### 10.3 Compliance Reporting
*   **Artifacts**: Automated generation of "Tenant Access Reports" from Audit Logs.
*   **Validation**: Periodic `checkov` scans of the Terraform state to ensure isolation rules are enforced.

---

## 11. Configuration & Metadata

### 11.1 Tenant Metadata
Stored in a `TenantRegistry` DynamoDB table (optional, for advanced features):
*   `Branding`: Custom logo/colors for the BFF UI.
*   `FeatureFlags`: Toggle specific Agent tools (e.g., "Enable Code Interpreter").
*   `Contacts`: Admin email addresses.

### 11.2 Configuration Validation
*   **Schema**: JSON Schema validation for all tenant configuration updates.
*   **Gatekeeper**: OPA/Cedar policies validate configuration changes before applying (e.g., "Cannot increase quota > 1000 without approval").

---

## 12. Support & Operations

### 12.1 Administrative Access
*   **Role**: `AgentCore-Support-Role`.
*   **Access**: Read-only access to Tenant Logs (if permitted by policy). No access to S3 Memory data.
*   **Tool**: CLI tool `acore-admin` for troubleshooting specific `session_ids`.

### 12.2 Cost Allocation
*   **Tagging**: All resources tagged with `AppID`.
*   **Metering**: Cost Calculator script parses CloudWatch Logs to attribute Lambda duration and Token usage to specific `TenantIDs` for chargeback.

### 12.3 SLAs
*   **Availability**: Bound by AWS Regional SLAs (typically 99.9%).
*   **Latency**: P99 < 2s for non-streaming responses. P99 < 500ms for Time-to-First-Token (streaming).

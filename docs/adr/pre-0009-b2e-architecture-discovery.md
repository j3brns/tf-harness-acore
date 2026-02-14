# Pre-ADR 0009: Detailed Architecture Discovery & Feasibility Assessment

## Status

Superseded by ADR 0009. Retained for discovery history.

## 1. Objective
Record the exhaustive discovery process, technical evidence, and feasibility analysis for publishing **Strands SDK** agents to a B2E environment using **Entra ID** and **Bedrock AgentCore**.

## 2. Technical Evidence & Findings

### 2.1. API Gateway Streaming (The Nov 2025 Update)
We validated that response streaming is the primary differentiator for the publishing layer.
*   **REST API (v1) Capabilities:**
    *   Supports **Payload Response Streaming** for `AWS_PROXY`.
    *   **Limits:** First 10MB unrestricted; subsequent data throttled to 2MB/s.
    *   **Timeout:** Supports long-running execution up to 15 minutes (critical for Deep Research agents).
*   **HTTP API (v2) Capabilities:**
    *   **NO Streaming.** All responses are buffered.
    *   **Constraint:** Use of HTTP API would result in a "dead" UI for 30-60 seconds while the LLM generates a comprehensive research response.
*   **Verdict:** REST API is the mandatory choice for GenAI/Strands UX.

### 2.2. WebIdentity & STS Exchange Flow
We assessed how to handle **Microsoft Entra ID** tokens without using Cognito.
*   **Discovery Result:** Bedrock AgentCore's `Inbound JWT Authorizer` can validate tokens directly, but using an **STS Exchange** at the Gateway layer is superior for B2E.
*   **The Sequence:**
    1.  Frontend sends **Entra ID JWT** (Bearer).
    2.  Lambda Proxy calls `sts:AssumeRoleWithWebIdentity` using the **OIDC Identity Provider** (arn:aws:iam::...:oidc-provider/login.microsoftonline.com/...).
    3.  AWS validates the token against Entra ID's `/.well-known/openid-configuration`.
    4.  The Proxy signs the `InvokeAgent` call with the resulting **Temporary Credentials**.
*   **Benefits:** This enables fine-grained IAM scopic logic (e.g., `Condition: { "StringLike": { "login.microsoftonline.com/...:sub": "user-guid" } }`).

### 2.3. The 3-Legged OAuth (3LO) "Double-Bounce"
Standard Bedrock 3LO documentation assumes a simple setup. Our discovery surfaced a complex requirement for B2E apps:
*   **The Loop:**
    *   **Redirect 1 (Auth):** User is redirected to the external IdP (e.g., Jira).
    *   **Redirect 2 (Code Validation):** Jira redirects the user back to **Bedrock's managed callback** (`https://bedrock-agentcore.../callback`).
    *   **Redirect 3 (App Finalization):** Bedrock redirects the user to our **API Gateway Endpoint** (`/auth/callback`).
*   **Requirement:** The API Gateway **MUST** implement a handler for `/auth/callback` that invokes the `CompleteResourceTokenAuth` API. Without this, the token is never ingested into the **AgentCore Identity Vault**.

### 2.4. Agent Discovery & Manifests
We analyzed how agents find each other (A2A) and how UIs find agents (Northbound).
*   **A2A Mechanism:** Uses **Agent Cards** (`/.well-known/agent-card.json`) for protocol negotiation.
*   **Discovery Gap:** Bedrock's `ListAgents` API only returns ARNs and metadata. It does not provide the "Business Menu" (Icons, Pricing, Department) needed for a B2E Portal.
*   **Feasibility of MCP:** The **AgentCore Gateway** serves as the "Aggregator." It exposes a `tools/list` manifest which can serve as the **Northbound Discovery Manifest**.

## 3. Feasibility Analysis: Strands SDK Integration

| Feature | Support in AgentCore | Implementation Pattern |
| :--- | :--- | :--- |
| **Managed Runtime** | Yes | `null_resource` + `create-agent-runtime` |
| **A2A Inbound** | Yes | `CustomJWTAuthorizerConfiguration` |
| **Identity Vault** | Yes | Managed by `Workload Identity` resources |
| **Ingestion** | Partial | CLI-based (`agentcore launch`) due to provider gaps |

## 4. Identified Trade-offs

### 4.1. Security vs. Latency
*   **Trade-off:** Implementing a Lambda Authorizer + STS Exchange adds ~150ms to the first byte.
*   **Decision:** Accept the latency. The risk of long-term credential exposure on the client is unacceptable in an enterprise (B2E) context.

### 4.2. Universal Codex vs. Native Docs
*   **Trade-off:** Maintaining `AGENTS.md` vs. relying on individual module READMEs.
*   **Decision:** Centralize in `AGENTS.md` (Codex) to ensure all agents (Human, Gemini, Claude) share the same constraints regarding CLI patterns and IAM wildcards.

## 5. Deployment Strategy (Releases)
We determined that **API Gateway Stages** (dev, test, prod) should map 1:1 to **Bedrock Agent Aliases**. This ensures that code changes in the Strands SDK can be promoted through environments safely without changing the endpoint URL for the client.

## 6. Conclusion
The proposed architecture -- **REST API with Streaming, STS-based WebIdentity Federation, and a Dedicated Callback Handler** -- is the only path that satisfies the enterprise requirement for security, UX, and multi-agent (Strands) collaboration.

**Superseded:** See **ADR 0009** for the formal architectural decision.

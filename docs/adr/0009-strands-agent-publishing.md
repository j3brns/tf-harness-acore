# ADR 0009: Strands Agent Publishing & Identity Architecture

## Status
Accepted

## Context
We are deploying AI agents built with the **AWS Strands SDK** (DeepAgents) on **Bedrock AgentCore**. To make these agents accessible to enterprise users (B2E), we need a publishing architecture that satisfies specific constraints:

1.  **Streaming:** The chat interface requires token-by-token response streaming for acceptable UX.
2.  **Identity:** Users authenticate via **Microsoft Entra ID** (Azure AD). There is no Amazon Cognito.
3.  **Security:** We must use **AWS WebIdentity Federation** (OIDC) to propagate user identity to the Bedrock runtime.
4.  **Guardrails:** Safety checks must be layered (Pre-flight + In-session).

The default `bedrock-agent-runtime` endpoint supports direct invocation but requires SigV4 signing, which is complex for frontend clients. HTTP APIs (API Gateway v2) do not support response streaming (as of Nov 2025).

## Decision
We will implement an **Enterprise REST Pattern** using Amazon API Gateway (REST) and a Lambda Proxy.

### 1. High-Level Architecture

```mermaid
graph LR
    User[User / Web App] -->|1. JWT (Bearer)| APIGW[API Gateway (REST)]
    APIGW -->|2. Authorize| Auth[Lambda Authorizer]
    Auth -->|3. Validate| Entra[Entra ID OIDC]
    APIGW -->|4. Stream| Proxy[Lambda Proxy]
    Proxy -->|5. AssumeRole| STS[AWS STS]
    Proxy -->|6. InvokeAgent| Bedrock[Bedrock Agent Runtime]
```

### 2. Authentication Flow (WebIdentity)

We will use the **Exchange Pattern** to securely propagate identity:

1.  **Client:** Acquires OIDC `id_token` from Entra ID. Sends `POST /chat` with `Authorization: Bearer <token>`.
2.  **Authorizer:** Validates token signature, issuer (`iss`), and audience (`aud`). Checks Entra Group membership for coarse-grained access.
3.  **Proxy:**
    *   Calls `sts:AssumeRoleWithWebIdentity`.
    *   **Trust Policy:** Configured to trust the Entra ID Tenant.
    *   **Result:** Receives temporary AWS credentials (AccessKey, SecretKey, SessionToken) scoped to the user.
4.  **Invocation:** The Proxy uses these temporary credentials to sign the `bedrock:InvokeAgent` request via the AWS SDK.

### 3. API Gateway Configuration (REST)

*   **Protocol:** REST API (Edge-optimized or Regional).
*   **Integration Type:** `AWS_PROXY` (Lambda).
*   **Response Streaming:** **ENABLED**. The Lambda Proxy will write to the response stream as chunks arrive from Bedrock.
*   **Routes:**
    *   `POST /chat/{agentId}`: Direct conversation.
    *   `GET /auth/callback`: Handles 3LO redirects (see below).

### 4. 3-Legged OAuth (3LO) Handling

For agents requiring user-level access to tools (e.g., Jira, Salesforce):

1.  Agent returns a "Need Auth" signal.
2.  UI redirects user to the authorization URL.
3.  **Constraint:** The redirect callback must be public.
4.  **Solution:** API Gateway exposes `GET /auth/callback`.
    *   This endpoint receives the `code`.
    *   It invokes `bedrock-agent-runtime:CompleteResourceTokenAuth`.
    *   The token is stored in the **AgentCore Identity Vault**.

### 5. Guardrail Layering

*   **Layer 1 (Gateway):** Lambda Authorizer performs basic input validation (e.g., PII regex, payload size).
*   **Layer 2 (Agent):** Bedrock Guardrail attached to the **Agent Alias**. This is the primary safety enforcement.
*   **Layer 3 (Runtime):** Strands SDK policies enforcing logical constraints.

## Consequences

### Positive
*   **Streaming UX:** Solves the buffering issue of HTTP APIs.
*   **Strict Security:** No long-term credentials on the client. Identity is federated all the way to the runtime.
*   **Enterprise Integration:** Native support for Entra ID without Cognito mediation.

### Negative
*   **Latency:** The Lambda Authorizer + STS Exchange adds ~100-200ms overhead to the initial handshake.
*   **Complexity:** Requires managing a dedicated Lambda Proxy and Authorizer codebase.

## References
*   [AWS Bedrock Agent Runtime API](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-runtime-api.html)
*   [API Gateway Response Streaming](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-response-streaming.html)
*   [Pre-ADR 0010: Service Discovery](pre-0010-service-discovery.md) (Context for finding agents)

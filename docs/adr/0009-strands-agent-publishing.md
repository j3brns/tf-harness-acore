# ADR 0009: Strands Publishing, Identity, and Release Architecture

## Status
Accepted

## Context
Deploying Strands SDK agents requires a robust publishing layer that handles:
1.  **Response Streaming:** Mandatory for chat UX.
2.  **B2E Identity:** Microsoft Entra ID integration without Cognito.
3.  **Complex Routing:** Supporting both direct agent access and a unified supervisor (router) agent.
4.  **Safe Releases:** Decoupling API endpoints from agent version changes.
5.  **3-Legged OAuth:** Securely ingesting 3rd-party tokens (Salesforce, Jira) into the AgentCore Identity Vault.

## Decision
We will implement an **Enterprise REST Proxy** using API Gateway (REST) and Lambda.

### 1. Unified Identity Flow (WebIdentity STS Exchange)
To propagate the human user's identity (Entra ID) to the agent runtime:
- **Flow:** Client JWT (Entra) -> API Gateway -> Lambda Authorizer -> Lambda Proxy.
- **Exchange:** The Proxy calls `sts:AssumeRoleWithWebIdentity`.
- **Auth:** The resulting SigV4 credentials are used to sign the `bedrock:InvokeAgent` call.
- **Benefit:** This allows Bedrock policies to use `${aws:PrincipalTag/email}` for fine-grained user-level authorization.

### 2. Multi-Agent Routing Logic
We will support two distinct routing modes:
- **Supervisor Mode (`POST /chat`):** Maps to a central "Supervisor" agent. The Supervisor uses A2A discovery (ADR 0010) to delegate tasks to specialist agents.
- **Direct Mode (`POST /agents/{agentId}/invoke`):** Allows power users or internal systems to target a specific agent directly. The Lambda Proxy extracts `agentId` from the path.

### 3. Release & Stage Management
To ensure zero-downtime releases:
- **Mapping:** API Gateway **Stages** map 1:1 to Bedrock **Agent Aliases**.
- **Dev Stage:** Invokes agent alias `DRAFT` or `DEV`.
- **Prod Stage:** Invokes agent alias `PROD`.
- **Implementation:** The Lambda Proxy uses `event.requestContext.stage` to look up the target Alias ARN in an environment map.

### 4. 3LO "Double-Bounce" Handler
We will publish a dedicated route: `GET /auth/callback`.
- **Purpose:** Ingests tokens from 3rd-party IdPs.
- **Logic:** Bedrock redirects the user here after code validation. The handler calls `bedrock-agent-runtime:CompleteResourceTokenAuth` using the user's `session_id`.
- **Storage:** Tokens are stored in the managed **AgentCore Identity Vault**.

### 5. Streaming Configuration
- **API Type:** REST API (Edge-optimized).
- **Settings:** Enable **Payload Response Streaming** on the integration.
- **Timeout:** Set to **900 seconds (15 minutes)** to accommodate deep research agents.

## Consequences

### Positive
- **UX:** Real-time token streaming.
- **Security:** Standardized WebIdentity federation.
- **Operations:** Safe environment-based promotion.

### Negative
- **Cost:** REST API + Lambda Proxy is more expensive than a simple HTTP API.
- **Maintenance:** Requires managing the custom STS exchange and callback logic.

## References
- [Pre-ADR 0009: Architecture Discovery](pre-0009-b2e-architecture-discovery.md)
- [ADR 0010: Service Discovery](0010-service-discovery.md)
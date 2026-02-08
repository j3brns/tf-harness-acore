# ADR 0010: Agent Mesh & Service Discovery Architecture

## Status
Accepted

## Context
In a multi-agent system (Strands), agents must be able to discover peer capabilities at runtime without hardcoding ARNs. We need a registry that supports both "Northbound" (Human discovery) and "East-West" (Agent-to-Agent discovery).

## Decision
We will implement a **Dual-Registry Discovery** model using AWS Cloud Map and the Agent Card protocol.

### 1. East-West Discovery (AWS Cloud Map)
For A2A communication, we will use **AWS Cloud Map** as the definitive registry.
- **Namespace:** `agents.local` (Private DNS).
- **Service Name:** Logical function (e.g., `research`, `finance`).
- **Registration:** Every `agent_runtime` deployment registers its endpoint URL as an Instance in Cloud Map.
- **Resolution:** A calling agent queries Cloud Map by Service Name to get the target Runtime URL.

### 2. The Agent Card Protocol
Once a target URL is resolved via Cloud Map, the caller negotiates capabilities via the **Agent Card**:
- **Endpoint:** `GET /.well-known/agent-card.json`.
- **Logic:** The caller reads the card to understand the agent's input schema and protocol support (Strands/MCP).

### 3. Northbound Discovery (The Catalog API)
To populate the UI "Agent Menu":
- **Route:** `GET /agents` on API Gateway.
- **Implementation:** A Lambda resolver that queries Cloud Map instances and filters them based on the user's **Entra ID Group claims**.
- **Metadata:** Cloud Map attributes will store human-friendly fields like `icon_url` and `category`.

### 4. A2A Authentication (Context Propagation)
Discovery is only valid if followed by secure authentication.
- **Requirement:** All A2A calls MUST be authenticated using **Workload Tokens**.
- **The Flow:**
    1. Agent A (Caller) receives User JWT.
    2. Agent A resolution targets Agent B via Cloud Map.
    3. Agent A calls `GetWorkloadAccessTokenForJWT` to exchange the User JWT for an **Agent-to-Agent token**.
    4. Agent A invokes Agent B with the token.
    5. Agent B validates the token via its Inbound Authorizer.

## Consequences

### Positive
- **Scalability:** New agents become available instantly across the mesh.
- **Security:** Strict identity propagation ensures Guardrails follow the user context.
- **Decoupling:** Agents don't need to know each other's ARNs.

### Negative
- **Dependency:** Cloud Map becomes a critical failure point for multi-agent workflows.
- **Complexity:** Requires agents to implement resolution logic (using the AWS SDK).

## References
- [Pre-ADR 0010: Discovery Exploration](pre-0010-service-discovery.md)
- [Strands SDK A2A Protocol Specification]

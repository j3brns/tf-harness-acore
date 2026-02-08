# Pre-ADR 0010: Detailed Service Discovery & A2A Architecture

## 1. Objective
Define the Service Discovery and Agent-to-Agent (A2A) Registry architecture for the **Strands** multi-agent ecosystem. This document bridges the gap between individual agent deployments and a cohesive, discoverable agent mesh.

## 2. Technical Context & Gaps

### 2.1. The Strands A2A Protocol
Strands agents communicate using a decentralized protocol.
*   **Mechanism:** Every agent runtime exposes a standard endpoint: `GET /.well-known/agent-card.json`.
*   **Content:** This JSON card contains the agent's Name, Description, Input Schema, and Protocol Version.
*   **The Gap:** To read an agent's card, you must *already know* its endpoint URL. There is no built-in "Phone Book" in Bedrock AgentCore to list all available agent URLs.

### 2.2. Discovery Tiers
We identified two distinct discovery needs with different constraints:

#### Tier 1: Northbound Discovery (The "Menu")
*   **Consumer:** Frontend UI (Chat Application).
*   **Need:** "List all agents I (the user) am allowed to talk to."
*   **Metadata:** Display Name, Icon, Description, Category.
*   **Security:** Filtered by Entra ID Group claims.
*   **Solution:** **API Gateway Catalog Route** (`GET /agents`).
    *   Backed by a simple DynamoDB table or S3 JSON manifest updated during CI/CD.

#### Tier 2: East-West Discovery (The "Mesh")
*   **Consumer:** Supervisor Agent (Machine).
*   **Need:** "Find the endpoint for the 'Finance' capability."
*   **Latency:** Must be <10ms resolution.
*   **Solution:** **AWS Cloud Map (Service Discovery)**.
    *   **Registry:** `agents.internal` (Private DNS namespace).
    *   **Records:** `finance.agents.internal` -> `SRV` record pointing to the Runtime Endpoint.
    *   **Attributes:** Cloud Map allows custom attributes (e.g., `version`, `environment`) to support blue/green routing.

## 3. Architecture Proposal

### 3.1. The "Dual-Registry" Pattern
We will not try to force one registry to serve both masters.

| Feature | Northbound (Catalog) | East-West (Cloud Map) |
| :--- | :--- | :--- |
| **Primary Key** | Agent ID / Alias | Logical Service Name |
| **Protocol** | REST (JSON) | DNS / AWS SDK |
| **Security** | OIDC (User Context) | IAM (Machine Context) |
| **Update Trigger** | CI/CD Pipeline | Agent Startup / Deployment |

### 3.2. Integration with AgentCore Gateway
The **AgentCore Gateway** serves a specialized role:
*   It aggregates **MCP Tools** (Lambda functions).
*   Its `tools/list` API is effectively the **Tool Discovery Manifest**.
*   **Integration:** The Supervisor Agent treats the Gateway as its "Toolbox" but uses Cloud Map to find "Peer Agents."

## 4. Feasibility Assessment

*   **Cloud Map Integration:** Supported natively by ECS/Fargate, but for **AgentCore Runtime** (serverless), we must register instances explicitly via Terraform (`aws_service_discovery_instance`).
*   **Agent Card Availability:** Verified that Bedrock Runtime exposes `/.well-known/agent-card.json` automatically for all provisioned agents.

## 5. Next Steps
*   Formalize the **Cloud Map** namespace design in **ADR 0010**.
*   Define the **CI/CD hook** that populates the Northbound Catalog.

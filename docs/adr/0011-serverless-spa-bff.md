# ADR 0011: Serverless SPA & BFF (Token Handler Pattern)

## Status
Accepted

## Context
Exposing the Bedrock Agent to users requires a web interface (SPA). Direct access via the browser would require storing Entra ID tokens in `localStorage`, exposing them to XSS theft. We need a secure, serverless way to manage sessions.

## Decision
We will implement the **AWS Serverless Token Handler Pattern**.

### 1. Architecture Components
*   **Frontend Host:** Amazon S3 + CloudFront (origin for `/`).
*   **API Origin:** Amazon API Gateway (origin for `/api` and `/auth`).
*   **Session Store:** Amazon DynamoDB (encrypted).

### 2. The OAuth Agent (Regional Lambda)
We will deploy a specific Lambda function to handle OIDC lifecycle events:
*   `GET /auth/login`: Redirects to Entra ID Authorization Endpoint.
*   `GET /auth/callback`:
    1.  Receives `code`.
    2.  Calls Entra ID `token` endpoint (Regional Lambda avoids 5s timeout).
    3.  Writes tokens to DynamoDB (TTL = token expiry).
    4.  Returns `Set-Cookie: session_id=...; Secure; HttpOnly; SameSite=Strict`.

### 3. The OAuth Proxy (Lambda Authorizer)
The API Gateway will use a **Request Authorizer**:
*   **Input:** `Cookie` header.
*   **Logic:** Reads `session_id`, looks up `access_token` in DynamoDB.
*   **Output:** Returns an IAM Policy allowing the request AND injects the `access_token` into the context.
*   **Integration:** The backend Lambda Proxy reads this token and invokes **AgentCore Runtime** via `InvokeAgentRuntime` over HTTPS (OAuth-compatible), forwarding the bearer token.
*   **Streaming:** The proxy uses Lambda response streaming (Node.js runtime) and API Gateway response transfer mode `STREAM` to pass through runtime chunks as NDJSON (`application/x-ndjson`).

### 4. Entra ID Configuration
*   **App Registration:** "Single Page Application" platform is *incorrect* for this pattern.
*   **Configuration:** Register as a **Web Application** (Confidential Client) because the exchange happens securely on the server (Lambda).
*   **Security:** Implements **PKCE (Proof Key for Code Exchange)** for all OIDC flows to prevent authorization code injection, even for confidential clients.

### 5. Response Streaming
*   **Requirement:** Agent interactions (e.g., Deep Research) often exceed 29s.
*   **Implementation:** The `/api/chat` endpoint utilizes **Native Response Streaming** enabled by **AWS Provider v6.0+**.
*   **Configuration:** `response_transfer_mode = "STREAM"` with a `timeout_milliseconds = 900000` (15 minutes).

## Consequences

### Positive
*   **Security:** "Bank-grade" security. Tokens are completely invisible to the client. PKCE prevents interception.
*   **Scalability:** Serverless components scale to zero.
*   **UX:** Native 15-minute streaming prevents 504 timeouts during long-running agent tasks.

### Negative
*   **Complexity:** Requires maintaining the Token Handler Lambda code.
*   **Cost:** DynamoDB RCU/WCU for session management.

## References
*   [Pre-ADR 0011: Discovery & Assessment](pre-0011-serverless-spa-bff.md)
*   [Issue #4: RFC Implementation](https://github.com/j3brns/tf-harness-acore/issues/4)

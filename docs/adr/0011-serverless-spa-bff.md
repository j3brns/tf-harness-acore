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
*   **Integration:** The backend Lambda Proxy (from ADR 0009) reads this token from the context/header to perform the **STS WebIdentity Exchange**.

### 4. Entra ID Configuration
*   **App Registration:** "Single Page Application" platform is *incorrect* for this pattern.
*   **Configuration:** Register as a **Web Application** (Confidential Client) because the exchange happens securely on the server (Lambda). This allows us to use a Client Secret if needed (though Certificate auth is preferred).

## Consequences

### Positive
*   **Security:** "Bank-grade" security. Tokens are completely invisible to the client.
*   **Scalability:** Serverless components scale to zero.
*   **Compliance:** Access logs (CloudFront + API Gateway) provide full audit trail.

### Negative
*   **Complexity:** Requires maintaining the Token Handler Lambda code.
*   **Cost:** DynamoDB RCU/WCU for session management.

## References
*   [Pre-ADR 0011: Discovery & Assessment](pre-0011-serverless-spa-bff.md)
*   [Issue #4: RFC Implementation](https://github.com/j3brns/tf-harness-acore/issues/4)

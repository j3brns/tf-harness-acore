# Pre-ADR 0011: Serverless SPA & BFF Architecture Discovery

## 1. Context
We need to serve a Single Page Application (SPA) that acts as the frontend for our Bedrock Agents. The enterprise requirement is to use **Microsoft Entra ID** for authentication.

**The Challenge:** Storing Access Tokens (JWTs) in the browser (LocalStorage/SessionStorage) is vulnerable to XSS attacks. The "Implicit Flow" is deprecated.

## 2. Technical Assessment: The "BFF" Pattern
We evaluated patterns to implement a **Backend-for-Frontend (BFF)** that keeps tokens on the server side.

### 2.1. Lambda@Edge (The Anti-Pattern)
*   *Idea:* Handle the entire OIDC handshake in a Lambda@Edge Viewer Request.
*   *Finding:* Lambda@Edge has a hard **5-second timeout** and body size limits. OIDC code exchanges with Entra ID often exceed this, causing 502 errors.
*   *Verdict:* **Rejected** for the core handshake logic.

### 2.2. The "Token Handler" Pattern (Recommended)
This pattern splits the BFF into two components:

1.  **The OAuth Agent (Regional Lambda):**
    *   Exposes `/auth/login`, `/auth/callback`, `/auth/refresh`.
    *   Performs the heavy network calls to Entra ID.
    *   Stores the Access/Refresh tokens in a secure **DynamoDB** table (encrypted).
    *   Issues an opaque, encrypted `session_id` in a Secure HTTP-only Cookie.

2.  **The OAuth Proxy (API Gateway Authorizer):**
    *   Intercepts requests to `/api/*`.
    *   Reads the `session_id` cookie.
    *   Lookups up the real Access Token in DynamoDB.
    *   **Translation:** Injects the Access Token into the `Authorization` header before the request hits the Bedrock Agent Proxy.

## 3. Trade-offs

| Decision | Pros | Cons |
| :--- | :--- | :--- |
| **Token Handler** | Zero XSS risk (tokens never touch browser). | Higher complexity (DynamoDB + Extra Lambda). |
| **CloudFront** | Global caching for SPA assets. | Configuring behaviors for `/api` vs `/*` is tricky. |
| **Regional Lambda** | 15m timeout (safe for OIDC). | Slightly higher latency than Edge for auth checks (negligible). |

## 4. Proposed Architecture

```mermaid
graph LR
    Browser[SPA (Browser)] -->|1. Cookie| CloudFront
    CloudFront -->|2. /api/*| APIGW[API Gateway]
    APIGW -->|3. Authorizer| AuthLambda[Token Proxy Lambda]
    AuthLambda -->|4. Get Token| DDB[DynamoDB]
    APIGW -->|5. Bearer Token| Proxy[Bedrock Proxy]
    Proxy -->|6. Invoke| Bedrock
```

## 5. Next Steps
*   Formalize in **ADR 0011**.
*   Implement `modules/spa-bff` Terraform module.

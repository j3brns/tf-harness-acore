# AgentCore BFF (Serverless SPA/Token Handler)

This module implements the **Serverless Token Handler Pattern** (ADR 0011) to secure Bedrock Agents behind an Entra ID authenticated frontend.

## Architecture

*   **Frontend**: S3 + CloudFront (SPA Hosting).
*   **API**: Amazon API Gateway (REST).
*   **Auth**: "Token Handler" Lambdas (Login/Callback) + DynamoDB Session Store.
*   **Proxy**: Lambda Proxy to AgentCore Runtime (`InvokeAgentRuntime`) with streaming response support (Node.js runtime).

## Usage

```hcl
module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff = true
  agent_name = var.agent_name
  region     = var.region
  agentcore_region = var.region
  environment = var.environment
  agentcore_runtime_arn = module.agentcore_runtime.runtime_arn

  # Auth Configuration
  oidc_client_id         = var.oidc_client_id
  oidc_issuer            = "https://login.microsoftonline.com/..."
  oidc_client_secret_arn = "arn:aws:secretsmanager:..."
}
```

## Regional Settings
* `region`: Region for BFF resources (API Gateway, Lambda, DynamoDB, S3, CloudFront).
* `agentcore_region`: Region for AgentCore runtime invocation (defaults to `region`).
* `agentcore_runtime_arn`: Runtime ARN to invoke.

## Streaming Response Format

The proxy streams `application/x-ndjson` where each line is a JSON object:
- `{"type":"meta","sessionId":"..."}`
- `{"type":"delta","delta":"text chunk"}`

## Known Failure Modes (Rule 16)

### 1. 502 Bad Gateway on `/auth/callback`
*   **Cause**: Lambda timeout or Entra ID connectivity issue.
*   **Fix**: Check CloudWatch Logs for `agentcore-bff-auth-*`. Ensure the Lambda has internet access (NAT Gateway if in VPC, or standard public access).

### 2. 403 Forbidden on `/api/chat`
*   **Cause**: Invalid or expired Session Cookie.
*   **Fix**: Clear browser cookies. Check DynamoDB table for session existence and TTL. Check `agentcore-bff-authz-*` logs.

### 3. SPA 403 Access Denied
*   **Cause**: CloudFront OAC permission issue or S3 bucket policy sync delay.
*   **Fix**: Ensure `terraform apply` completed successfully. Verify S3 bucket policy allows the CloudFront Distribution ARN.

### 4. CORS Errors
*   **Cause**: API Gateway not returning CORS headers.
*   **Fix**: The module assumes CloudFront proxies everything (`/api/*`). Ensure you are accessing via the CloudFront URL, not the API Gateway URL directly (which has different origin).

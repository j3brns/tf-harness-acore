# AgentCore BFF (Serverless SPA/Token Handler)

This module implements the **Serverless Token Handler Pattern** (ADR 0011) to secure Bedrock Agents behind an Entra ID authenticated frontend.

## Architecture

*   **Frontend**: S3 + CloudFront (SPA Hosting).
    CloudFront rewrites extension-less SPA routes to `/index.html` at viewer-request time, while preserving `/api/*` and `/auth/*` origin status codes.
*   **API**: Amazon API Gateway (REST).
*   **Auth**: "Token Handler" Lambdas (Login/Callback) + DynamoDB Session Store.
    The request authorizer validates the session cookie against the stored session record and JWT tenant claims before allowing `/api/*` calls.
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

  # Optional compliance feature (Issue #30)
  logging_bucket_id             = module.agentcore_foundation.access_logs_bucket_id
  enable_audit_log_persistence  = true
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

## Audit Log Persistence (Issue #30)

When `enable_audit_log_persistence = true` and `logging_bucket_id` is set, the proxy writes a per-request "shadow JSON" audit record to S3 under:

- `audit/bff-proxy/events/{app_id}/{tenant_id}/year=YYYY/month=MM/day=DD/*.json`

The module also provisions:

- a Glue catalog database/table for the JSON records
- an Athena workgroup with SSE-S3 query result encryption

Useful outputs:

- `audit_logs_s3_prefix`
- `audit_logs_athena_database`
- `audit_logs_athena_table`
- `audit_logs_athena_workgroup`

## Optional CloudFront WAF Association (Issue #54)

Enterprise deployments can attach a WAFv2 Web ACL to the CloudFront distribution for internet-facing threat protection (rate limiting, geo-blocking, managed rule sets such as the AWS Managed Rules Common Rule Set).

### Constraints

- The Web ACL **must** be created in `us-east-1` with `scope = "CLOUDFRONT"`. CloudFront only accepts global-scope WAFv2 ACLs.
- This is **separate** from `waf_acl_arn`, which attaches a REGIONAL Web ACL to the API Gateway stage.
- Enabling WAF incurs additional AWS cost per million requests evaluated. Refer to [AWS WAF pricing](https://aws.amazon.com/waf/pricing/) before enabling.

### Usage

```hcl
module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff = true
  # ... other required variables ...

  # Optional: attach a CloudFront-scope WAFv2 Web ACL (must be in us-east-1)
  cloudfront_waf_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/my-cf-acl/abc-123"
}
```

The harness default is `cloudfront_waf_acl_arn = ""` (WAF disabled on CloudFront).

### Operational Considerations

| Topic | Guidance |
|---|---|
| **Managed rules** | Start with `AWSManagedRulesCommonRuleSet` and `AWSManagedRulesAmazonIpReputationList`. Add `AWSManagedRulesBotControlRuleSet` for bot mitigation if needed. |
| **False positives** | Initially deploy rules in `COUNT` mode; promote to `BLOCK` after a baselining period (≥48 h of production traffic). |
| **WAF logging** | Enable WAF logging to a CloudWatch log group or Kinesis Firehose -> S3. Use the BFF `logging_bucket_id` bucket as the Firehose destination for consolidated access and WAF logs. |
| **Geo-blocking** | Add a geographic match rule to the Web ACL if service is restricted to specific regions. Do not use CloudFront geo-restriction for this (WAF geo match is more granular and auditable). |
| **IP rate limiting** | Add a rate-based rule (threshold ≥ 2000 req/5 min per IP recommended as a starting baseline) to protect the `/auth/*` OIDC callback path. |
| **Alert on BLOCK actions** | Create a CloudWatch metric filter on the WAF log group and alarm on `terminatingRuleType = REGULAR` action `BLOCK` to detect attack surges. |

## Known Failure Modes (Rule 16)

### 1. 502 Bad Gateway on `/auth/callback`
*   **Cause**: Lambda timeout or Entra ID connectivity issue.
*   **Fix**: Check CloudWatch Logs for `agentcore-bff-auth-*`. Ensure the Lambda has internet access (NAT Gateway if in VPC, or standard public access).

### 2. 403 Forbidden on `/api/chat`
*   **Cause**: Invalid or expired Session Cookie.
*   **Fix**: Clear browser cookies. Check DynamoDB table for session existence and TTL. Check `agentcore-bff-authz-*` logs. The authorizer also denies if the cookie tenant/session does not match the stored session or JWT tenant claim.

### 3. SPA 403 Access Denied
*   **Cause**: CloudFront OAC permission issue or S3 bucket policy sync delay.
*   **Fix**: Ensure `terraform apply` completed successfully. Verify S3 bucket policy allows the CloudFront Distribution ARN.

### 4. CORS Errors
*   **Cause**: API Gateway not returning CORS headers.
*   **Fix**: The module assumes CloudFront proxies everything (`/api/*`). Ensure you are accessing via the CloudFront URL, not the API Gateway URL directly (which has different origin).

### 5. API 4xx Returning `index.html` (Regression Guard)
*   **Cause**: Misconfigured CloudFront SPA fallback using distribution-wide `custom_error_response`.
*   **Fix**: Keep SPA fallback on the default S3 behavior via the viewer-request CloudFront Function (`spa_route_rewrite`). Do not use distribution-wide `403/404 -> /index.html` rewrites.

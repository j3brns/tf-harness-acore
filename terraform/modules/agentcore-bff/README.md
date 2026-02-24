# AgentCore BFF (Serverless SPA/Token Handler)

This module implements the **Serverless Token Handler Pattern** (ADR 0011) to secure Bedrock Agents behind an Entra ID authenticated frontend.

## Architecture

*   **Frontend**: S3 + CloudFront (SPA Hosting).
    CloudFront rewrites extension-less SPA routes to `/index.html` at viewer-request time, while preserving `/api/*` and `/auth/*` origin status codes.
*   **API**: Amazon API Gateway (REST).
*   **Auth**: "Token Handler" Lambdas (Login/Callback) + DynamoDB Session Store.
    The request authorizer validates the session cookie against the stored session record and JWT tenant claims before allowing `/api/*` calls.
    On the first successful OIDC callback for a tenant, the callback handler performs JIT logical onboarding (Rule 14.5) by creating deterministic tenant metadata and baseline policy-attachment records in DynamoDB before issuing the session cookie.
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

## JIT Tenant Onboarding (Issue #28)

The auth callback (`/auth/callback`) performs retry-safe, idempotent JIT onboarding for the authenticated tenant using conditional DynamoDB writes:

- `TENANT#META` metadata record (tenant root prefix + session partition key)
- baseline policy attachment records under `POLICY#BASELINE#*`
- tenant-scoped session record (`SESSION#...`) only after onboarding records are ensured

If a previous attempt partially succeeded, the callback reuses existing onboarding records after verifying invariant fields instead of creating duplicates.

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

## Custom Domains & SSL (Issue #53)

Enterprise deployments can configure a custom domain name (e.g., `agent.example.com`) for the BFF CloudFront distribution. This requires providing an ACM certificate ARN.

### Constraints

- The ACM certificate **must** be created in `us-east-1`. CloudFront only accepts certificates from this region for global distributions.
- You must separately configure a DNS record (e.g., CNAME in Route 53 or your DNS provider) pointing the custom domain to the CloudFront distribution's domain name.
- The `spa_url` output will reflect the custom domain if configured.

### Usage

```hcl
module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff = true
  # ... other required variables ...

  # Optional: custom domain and ACM certificate
  custom_domain_name  = "agent.example.com"
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc12345-def6-7890-ghij-klmnopqrstuv"
}
```

### Operational Considerations

| Topic | Guidance |
|---|---|
| **Managed rules** | Start with `AWSManagedRulesCommonRuleSet` and `AWSManagedRulesAmazonIpReputationList`. Add `AWSManagedRulesBotControlRuleSet` for bot mitigation if needed. |
| **False positives** | Initially deploy rules in `COUNT` mode; promote to `BLOCK` after a baselining period (≥48 h of production traffic). |
| **WAF logging** | Enable WAF logging to a CloudWatch log group or Kinesis Firehose -> S3. Use the BFF `logging_bucket_id` bucket as the Firehose destination for consolidated access and WAF logs. |
| **Geo-blocking** | Add a geographic match rule to the Web ACL if service is restricted to specific regions. Do not use CloudFront geo-restriction for this (WAF geo match is more granular and auditable). |
| **IP rate limiting** | Add a rate-based rule (threshold ≥ 2000 req/5 min per IP recommended as a starting baseline) to protect the `/auth/*` OIDC callback path. |
| **Alert on BLOCK actions** | Create a CloudWatch metric filter on the WAF log group and alarm on `terminatingRuleType = REGULAR` action `BLOCK` to detect attack surges. |

## Checkov Classification (Issue #78)

Issue `#78` classifies BFF Checkov findings that are intentional harness defaults and adds resource-level skips with explicit rationale.
These skips preserve current harness behavior and document where enterprise controls are optional or workload-specific.

### Intentional Harness Defaults (Skipped in Code)

- `CKV_AWS_119` (DynamoDB CMK): BFF sessions use AWS-managed DynamoDB SSE by default per ADR-0008; CMK is an enterprise/regulatory opt-in.
- `CKV_AWS_120` / `CKV_AWS_225` (API Gateway caching): Caching is intentionally disabled because the BFF mixes OIDC auth endpoints and per-session streaming `/api/chat` traffic.
- `CKV_AWS_237` (API Gateway create-before-destroy): Zero-downtime REST API replacement requires a parallel cutover pattern and is not the harness default.
- `CKV_AWS_59` on `/auth/login` and `/auth/callback`: These OIDC entrypoints must be public by design; state/session checks occur in the token-handler Lambda flow.
- `CKV_AWS_310` (CloudFront origin failover): Active/passive failover requires additional multi-region topology and cutover logic beyond the default harness.
- `CKV_AWS_374` (CloudFront geo restriction): Geographic restrictions are tenant/workload policy decisions and should generally be enforced with WAF geo-match rules.

### BFF Hardening Completion (Issue #79)

Issue `#79` completes the remaining BFF Checkov hardening set from `#78`:

- `CKV_AWS_86` (CloudFront access logging): remediated by enabling `logging_config` on the distribution (reusing the shared logging bucket when configured, otherwise the SPA bucket).
- `CKV_AWS_50` (Lambda X-Ray tracing): remediated by enabling `tracing_config { mode = "Active" }` on the auth handler, authorizer, and proxy Lambdas.
- `CKV_AWS_272` (Lambda code signing): documented as a resource-level skip because signer profile/trust setup is an external dependency and not a harness default.

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

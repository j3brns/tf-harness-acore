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

  # Optional CloudFront access logging controls (Issue #64)
  # enable_cloudfront_access_logging = false
  # cloudfront_access_logs_prefix    = "cloudfront-access-logs/bff/"
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

## Optional CloudFront Access Logging (Issue #64)

The BFF CloudFront distribution supports **standard access logging** with explicit Terraform controls:

- `enable_cloudfront_access_logging` (default `true` to preserve current harness behavior)
- `cloudfront_access_logs_prefix` (default `cloudfront-access-logs/`)

When enabled, the module writes CloudFront standard logs to:

- the shared `logging_bucket_id` bucket (if provided), or
- the SPA bucket (fallback)

### Usage

```hcl
module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff = true
  # ... other required variables ...

  # Explicitly disable CloudFront standard access logs
  enable_cloudfront_access_logging = false
}
```

```hcl
module "agentcore_bff" {
  source = "./modules/agentcore-bff"

  enable_bff = true
  # ... other required variables ...

  # Keep logging enabled (default) and customize the S3 prefix
  cloudfront_access_logs_prefix = "cloudfront-access-logs/edge/"
}
```

### Operational Considerations

| Topic | Guidance |
|---|---|
| **Delivery semantics** | CloudFront standard logs are best-effort and can arrive late; use them for troubleshooting/analysis rather than exact billing reconciliation. |
| **Destination bucket requirements** | CloudFront standard logging (legacy S3 delivery used by `logging_config`) requires an S3 destination that supports ACLs; buckets with S3 Object Ownership set to **Bucket owner enforced** cannot receive these logs. |
| **Bucket separation** | AWS recommends a separate S3 bucket (or at least a separate prefix) for CloudFront logs, especially if you also use CloudFront standard logging v2 or other log producers. |
| **Retention / cost** | CloudFront does not charge to enable standard logs, but S3 storage/requests and downstream analytics (Athena/Glue/Firehose) incur cost. Apply lifecycle retention to the destination bucket/prefix. |
| **Analytics integration** | You can analyze CloudFront standard logs with Athena and co-locate them under a distinct prefix alongside BFF audit logs/WAF logs for shared observability workflows. |

References:
- AWS CloudFront Access Logs: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html
- AWS CloudFront Standard Logging (legacy, S3): https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/standard-logging-legacy-s3.html

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

## CloudFront Cache & Origin Request Policies (Issue #65)

The BFF CloudFront distribution uses explicit policy wiring instead of legacy per-behavior `forwarded_values`/TTL fields so cache behavior is easier to audit and reuse.

### Current Policy Model

- **Managed cache policy (`Managed-CachingDisabled`)** on SPA, `/api/*`, and `/auth/*` behaviors:
  disables CloudFront caching (`min/default/max TTL = 0`) and preserves immediate visibility for SPA updates plus non-cacheable auth/API traffic.
- **Managed origin request policy (`Managed-AllViewerExceptHostHeader`)** on `/api/*` and `/auth/*`:
  forwards viewer headers/cookies/query strings while removing the viewer `Host` header (CloudFront restores the origin host), which is the AWS-recommended model for API Gateway origins.
- **SPA default behavior** intentionally omits an origin request policy:
  the disabled cache policy already preserves the prior "forward nothing" behavior (no cookies, no query strings, no viewer headers) for the S3 SPA origin.

### Tradeoffs

- **Caching**: The harness keeps CloudFront caching disabled for all BFF paths to avoid stale `index.html`, OIDC callback/session issues, and per-session `/api/chat` response leakage.
- **Headers/Cookies/Query Strings (`/api/*`, `/auth/*`)**: The managed API Gateway-oriented origin request policy is broader than the previous hand-maintained header list, but avoids drift and preserves auth/CORS semantics without forwarding the viewer `Host` header.
- **SPA (`/*`)**: Minimal forwarding to S3 keeps cache/origin behavior deterministic and avoids unnecessary variation in object requests.

## Checkov Classification (Issue #78)

Issue `#78` classifies BFF Checkov findings that are intentional harness defaults and adds resource-level skips with explicit rationale.
These skips preserve current harness behavior and document where enterprise controls are optional or workload-specific.

### Intentional Harness Defaults (Skipped in Code)

- `CKV_AWS_119` (DynamoDB CMK): BFF sessions use AWS-managed DynamoDB SSE by default per ADR-0008; CMK is an enterprise/regulatory opt-in.
- `CKV_AWS_120` / `CKV_AWS_225` (API Gateway caching): Caching is intentionally disabled because the BFF mixes OIDC auth endpoints and per-session streaming `/api/chat` traffic.
- `CKV_AWS_237` (API Gateway create-before-destroy): Zero-downtime REST API replacement requires a parallel cutover pattern and is not the harness default.
- `CKV_AWS_59` on `/auth/login` and `/auth/callback`: These OIDC entrypoints must be public by design; state/session checks occur in the token-handler Lambda flow.
- `CKV2_AWS_53` on six tenant-admin API methods (Issue `#91`): These `HTTP_PROXY` routes validate tenant-admin request semantics in the BFF proxy Lambda, where Rule 14.1 tenant/session ownership checks and authorizer context are available. Skips are scoped to the six tenant-admin `aws_api_gateway_method` resources only.
- `CKV_AWS_310` (CloudFront origin failover): Active/passive failover requires additional multi-region topology and cutover logic beyond the default harness.
- `CKV_AWS_374` (CloudFront geo restriction): Geographic restrictions are tenant/workload policy decisions and should generally be enforced with WAF geo-match rules.

### BFF Hardening Completion (Issue #79)

Issue `#79` completes the remaining BFF Checkov hardening set from `#78`:

- `CKV_AWS_86` (CloudFront access logging): remediated by default-enabled `logging_config` on the distribution, with an explicit opt-out toggle for deployments that must disable or defer CloudFront standard logging.
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

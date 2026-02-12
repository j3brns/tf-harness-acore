# AgentCore Roadmap

This document outlines planned features and improvements for the Bedrock AgentCore framework.

## 🚀 High Priority (Reliability & Security)

### 1. OIDC Token Refresh Handler
*   **Problem:** Sessions currently expire after 60 minutes when the access token dies.
*   **Solution:** Implement a refresh sidecar in the Authorizer or a dedicated endpoint to use the stored `refresh_token` to rotate sessions seamlessly.

### 2. Multi-Tenant Session Partitioning
*   **Problem:** Current DynamoDB structure uses a single flat table for all sessions.
*   **Solution:** Update the session schema to include `tenant_id` or `application_id` as a Sort Key to support multi-tenant deployments.

### 3. OIDC Discovery Integration
*   **Problem:** OIDC endpoints (authorize/token) are currently constructed manually.
*   **Solution:** Implement auto-discovery by fetching `/.well-known/openid-configuration` from the ISSUER URL.

## 📈 Enterprise Features (Scale & Compliance)

### 4. Persistence for Audit Logs (Rule 15)
*   **Problem:** Audit logs (Shadow JSON) are currently ephemeral or stuck in CloudWatch.
*   **Solution:** Direct export of proxy interaction logs to S3 with Athena integration for long-term compliance reporting.

### 5. Cross-Account Gateway Support
*   **Problem:** BFF and AgentCore Gateway currently assume the same AWS account.
*   **Solution:** Enhance IAM roles and Resource-Based Policies to support cross-account tool invocation and identity propagation.

### 6. Automated Streaming Load Tester
*   **Problem:** Hard to verify the 15-minute "Streaming Wall" without manual testing.
*   **Solution:** A CLI utility that invokes the agent with a "long-running" mock tool to verify connectivity persistence up to 900s.

## 🛠️ Developer Experience (DX)

### 7. Native Swagger/OpenAPI Generation
*   **Problem:** MCP tools are defined in code but not documented for the frontend.
*   **Solution:** Automatically generate an OpenAPI spec from the MCP tools registry for use in the Web UI.

### 8. Frontend Component Library
*   **Problem:** Current frontend is a simple template.
*   **Solution:** Provide a library of React/Tailwind components for building specialized agent dashboards (e.g., streaming text blocks, tool call visualizations).

# AgentCore Roadmap

This document outlines planned features and improvements for the Bedrock AgentCore framework.

## ✅ Completed

- [x] **GitLab CI/CD & WIF Integration**: Secure credential-free deployments for enterprise GitLab on-prem/cloud.
- [x] **Expanded MCP Server Library**: Added S3 Tools and a Generic AWS CLI MCP server for agent orchestration.
- [x] **OIDC PKCE Support**: Hardened authorization code flow to prevent interception.
- [x] **Native 15-Minute Streaming**: Upgraded to AWS Provider v6.x to bypass the 29s REST API timeout.
- [x] **Multi-Tenant Session Partitioning**: Refactored DynamoDB to use composite keys (app_id + session_id).

## 🚀 High Priority (Reliability & Security)

- [ ] **OIDC Token Refresh Handler**
  * **Problem:** Sessions currently expire after 60 minutes when the access token dies.
  * **Solution:** Implement a refresh sidecar in the Authorizer or a dedicated endpoint to use the stored `refresh_token` to rotate sessions seamlessly.
  * **Issue:** #13

- [ ] **OIDC Discovery Integration**
  * **Problem:** OIDC endpoints (authorize/token) are currently constructed manually.
  * **Solution:** Implement auto-discovery by fetching `/.well-known/openid-configuration` from the ISSUER URL.
  * **Issue:** #15

## 📈 Enterprise Features (Scale & Compliance)

- [ ] **Persistence for Audit Logs (Rule 15)**
  * **Problem:** Audit logs (Shadow JSON) are currently ephemeral or stuck in CloudWatch.
  * **Solution:** Direct export of proxy interaction logs to S3 with Athena integration for long-term compliance reporting.
  * **Issue:** #15

- [ ] **Cross-Account Gateway Support**
  * **Problem:** BFF and AgentCore Gateway currently assume the same AWS account.
  * **Solution:** Enhance IAM roles and Resource-Based Policies to support cross-account tool invocation and identity propagation.
  * **Issue:** #16

- [ ] **Automated Streaming Load Tester**
  * **Problem:** Hard to verify the 15-minute "Streaming Wall" without manual testing.
  * **Solution:** A CLI utility that invokes the agent with a "long-running" mock tool to verify connectivity persistence up to 900s.
  * **Issue:** #17

## 🛠️ Developer Experience (DX)

- [ ] **Native Swagger/OpenAPI Generation**
  * **Problem:** MCP tools are defined in code but not documented for the frontend.
  * **Solution:** Automatically generate an OpenAPI spec from the MCP tools registry for use in the Web UI.
  * **Issue:** #18

- [ ] **Frontend Component Library**
  * **Problem:** Current frontend is a simple template.
  * **Solution:** Provide a library of React/Tailwind components for building specialized agent dashboards.
  * **Issue:** #19

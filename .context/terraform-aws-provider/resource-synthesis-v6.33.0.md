# Terraform AWS Provider Resource Synthesis (v6.33.0)

Checked on: 2026-02-22

This file summarizes the `hashicorp/aws` provider resource docs for Bedrock AgentCore and related Bedrock resources used by this repo's novation planning.

## Shared Patterns (Across These Resources)

- Most resources support optional `region` override and inherit provider region by default.
- Most resources support `tags`, and `tags_all` includes provider-level `default_tags`.
- AgentCore core resources (`gateway`, `gateway_target`, `agent_runtime`, `memory`, `browser`, `code_interpreter`) commonly use `30m` create/delete timeouts.
- Import blocks are documented for Terraform v1.5+ and are usable for state-transition migration workflows.

## Repo-Relevant Native Resources

### `aws_bedrockagentcore_gateway`

Purpose:
- Defines an AgentCore Gateway endpoint (MCP protocol), auth mode, protocol config, and optional interceptor config.

Key required arguments:
- `authorizer_type` (`CUSTOM_JWT` or `AWS_IAM`)
- `name`
- `protocol_type` (docs show `MCP`)
- `role_arn`

Notable optional arguments:
- `authorizer_configuration.custom_jwt_authorizer` (OIDC discovery URL + audiences/clients)
- `interceptor_configuration`
- `kms_key_arn`
- `protocol_configuration.mcp`

Notable outputs:
- `gateway_arn`
- `gateway_id`
- `gateway_url`
- `workload_identity_details.workload_identity_arn`

Import ID:
- Gateway ID (example format in docs: `GATEWAY1234567890`)

Repo note:
- Aligns with `null_resource.gateway` novation target in `docs/NOVATION_MATRIX.md`.

### `aws_bedrockagentcore_gateway_target`

Purpose:
- Attaches target tools/endpoints to an AgentCore Gateway (Lambda, MCP server, OpenAPI schema, Smithy model).

Key required arguments:
- `name`
- `gateway_identifier`
- `target_configuration`

Notable optional arguments:
- `credential_provider_configuration` (gateway IAM role / API key / OAuth)
- `target_configuration.mcp.mcp_server`
- complex tool/schema modeling blocks (`tool_schema`, `schema_definition`, nested `property`/`items`)

Notable outputs:
- `target_id`

Import ID:
- `gateway_identifier,target_id` (comma-delimited)

Repo note:
- High-value novation target for gateway tool plumbing.
- Schema complexity suggests careful phased migration and import planning.

### `aws_bedrockagentcore_agent_runtime`

Purpose:
- Provisions AgentCore runtime with artifact, network config, protocol, lifecycle, and optional authorizer config.

Key required arguments:
- `agent_runtime_name`
- `role_arn`
- `agent_runtime_artifact`
- `network_configuration`

Notable optional arguments:
- `authorizer_configuration.custom_jwt_authorizer`
- `lifecycle_configuration`
- `protocol_configuration` (`HTTP`, `MCP`, `A2A`)
- `request_header_configuration`
- `environment_variables`

Artifact shape notes:
- `agent_runtime_artifact` supports exactly one of:
  - `code_configuration`
  - `container_configuration`

Notable outputs:
- `agent_runtime_arn`
- `agent_runtime_id`
- `agent_runtime_version`
- `workload_identity_details.workload_identity_arn`

Import ID:
- `agent_runtime_id`

Repo note:
- Strong candidate for native migration in runtime module, but requires disciplined artifact packaging/state transition handling.

### `aws_bedrockagentcore_memory`

Purpose:
- Manages AgentCore memory resource with expiration and optional encryption/role controls.

Key required arguments:
- `name`
- `event_expiry_duration` (docs: positive integer, 7-365 days)

Notable optional arguments:
- `encryption_key_arn` (docs note AWS-managed encryption if omitted)
- `memory_execution_role_arn`

Notable outputs:
- `arn`
- `id`

Import ID:
- Memory ID (example format in docs: `MEMORY1234567890`)

Repo note:
- Matches Workstream A freeze-point rationale (`v6.33.0`) in local novation matrix.

### `aws_bedrock_inference_profile`

Purpose:
- Manages Bedrock inference profiles for model metrics/cost tracking.

Key required arguments:
- `name`
- `model_source`

Notable outputs:
- `arn`
- `id`
- `status`
- `type`
- `models[*].model_arn`

Import ID:
- `name` (docs import uses profile name/identifier)

Repo note:
- Standard Bedrock resource, not AgentCore-specific, but part of runtime/governance migration envelope.

### `aws_bedrock_guardrail`

Purpose:
- Manages Bedrock Guardrails, including content/topic/word/sensitive-info policies and optional cross-region routing config.

Key required arguments:
- `blocked_input_messaging`
- `blocked_outputs_messaging`
- `name`

Notable optional arguments:
- `content_policy_config`
- `contextual_grounding_policy_config`
- `sensitive_information_policy_config`
- `topic_policy_config`
- `word_policy_config`
- `kms_key_arn`
- `cross_region_config`

Notable outputs:
- `guardrail_arn`
- `guardrail_id`
- `status`
- `version`

Import ID:
- `guardrail_id,version` (comma-delimited; docs example uses `DRAFT`)

Repo note:
- Standard Bedrock governance resource; import syntax matters for migration because version is part of identity.

## Resources Present In Provider Docs But Marked `cli-required` In Local Matrix

### `aws_bedrockagentcore_browser`

Provider docs status:
- Present in `v6.33.0` docs

Key required arguments:
- `name`
- `network_configuration`

Notable optional arguments:
- `execution_role_arn`
- `recording` (S3 location for session recordings)

Import:
- Documented in provider docs (ID-based)

Repo implication:
- Native resource exists.
- Local matrix may still intentionally keep Browser on CLI bridge for operational/stability reasons.
- Update matrix wording if intent is "supported but deferred" rather than "no native support yet".

### `aws_bedrockagentcore_code_interpreter`

Provider docs status:
- Present in `v6.33.0` docs

Key required arguments:
- `name`
- `network_configuration`

Notable optional arguments:
- `execution_role_arn` (docs note required when `SANDBOX` network mode is used)
- `client_token`

Network modes:
- `PUBLIC`, `SANDBOX`, `VPC`

Import:
- Documented in provider docs (ID-based)

Repo implication:
- Native resource exists.
- Local matrix may intentionally defer migration for lifecycle/network complexity, but "no native support yet" appears out of date.

## AWS AgentCore Built-In Tools Context (AWS Knowledge MCP Cross-Check)

AWS AgentCore docs confirm Browser Tool and Code Interpreter are first-class built-in tools in the service architecture, with isolated execution environments, sessions, IAM integration, and network controls.

Why this matters for repo decisions:
- Provider-native support existing does not automatically mean immediate migration is low-risk.
- Tool lifecycle/session semantics and security/networking may still justify staged CLI usage in this repo.


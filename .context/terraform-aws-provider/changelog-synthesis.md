# Terraform AWS Provider Changelog Synthesis (Bedrock/AgentCore Focus)

Checked on: 2026-02-22

Source scanned:
- `hashicorp/terraform-provider-aws` `v6.33.0` `CHANGELOG.md` (covers prior releases in the same file)

## Why This Exists

This repo pins `hashicorp/aws ~> 6.33.0` as a Workstream A freeze point. This summary captures the Bedrock/AgentCore-relevant changelog signals that affect migration planning.

## Freeze-Point Read (6.30.0 -> 6.33.0)

Observed in scanned sections:
- `6.33.0` (2026-02-18): no Bedrock AgentCore-specific resource changes called out in the visible section
- `6.32.0` / `6.32.1` (2026-02-11 / 2026-02-13): no Bedrock AgentCore-specific changes called out in the visible sections
- `6.31.0` (2026-02-04): no Bedrock AgentCore-specific changes called out in the visible section
- `6.30.0` (2026-01-28): no Bedrock AgentCore-specific changes called out in the visible section

Interpretation:
- The `6.33.0` freeze point is reasonable as a stabilization baseline for Workstream A, because recent patch/minor activity does not appear to be rapidly changing the targeted AgentCore resource surfaces in the scanned sections.

## Earlier Bedrock/AgentCore Milestones (Relevant to Migration Planning)

### 6.17.0 (2025-10-16)
Changelog shows new AgentCore resources introduced, including:
- `aws_bedrockagentcore_agent_runtime`
- `aws_bedrockagentcore_browser`
- `aws_bedrockagentcore_code_interpreter`
- `aws_bedrockagentcore_gateway`
- `aws_bedrockagentcore_gateway_target`

### 6.18.0 (2025-10-23)
Changelog shows new resources including:
- `aws_bedrockagentcore_memory`
- additional AgentCore credential / workload identity resources

### 6.21.0 (2025-11-13)
Changelog includes:
- breaking change for `aws_bedrockagentcore_browser` network config naming (`network_mode_config` -> `vpc_config`)
- `aws_bedrockagentcore_gateway_target` enhancement adding `target_configuration.mcp.mcp_server`
- `aws_bedrockagentcore_gateway_target` enhancement making `credential_provider_configuration` optional

### 6.22.0 (2025-11-20)
Changelog includes:
- `aws_bedrockagentcore_agent_runtime` enhancement adding `agent_runtime_artifact.code_configuration`
- `aws_bedrockagentcore_agent_runtime` enhancement making `container_configuration` optional
- `aws_bedrock_guardrail` enhancements for content policy filter inputs/outputs

## Repo Planning Implications

1. Native support exists for more AgentCore resources than the local novation matrix currently advertises (notably Browser and Code Interpreter).
2. Repo policy/workstream decisions can still choose CLI bridge paths for risk control; this is a migration strategy decision, not only a provider availability question.
3. If Browser/Code Interpreter remain `cli-required`, update `docs/NOVATION_MATRIX.md` wording to reflect "deferred by repo policy" rather than "no native support yet".

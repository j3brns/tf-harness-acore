# Terraform AWS Provider Context (Repo-Specific Synthesis)

Checked on: 2026-02-22

This context pack summarizes current Terraform AWS Provider documentation relevant to this repository's Bedrock AgentCore migration workstream (Workstream A / novation matrix).

Scope:
- HashiCorp `terraform-provider-aws` `v6.33.0` resource docs for resources referenced by `docs/NOVATION_MATRIX.md`
- Provider changelog notes relevant to Bedrock AgentCore/Bedrock resources
- AWS AgentCore documentation context (via AWS Knowledge MCP) for built-in tools and service components

Repo alignment:
- Local provider freeze point is `hashicorp/aws ~> 6.33.0` in `terraform/versions.tf`
- Local migration SoT is `docs/NOVATION_MATRIX.md`

## Quick Conclusions

1. Native Terraform docs exist in `v6.33.0` for:
   - `aws_bedrockagentcore_gateway`
   - `aws_bedrockagentcore_gateway_target`
   - `aws_bedrockagentcore_agent_runtime`
   - `aws_bedrockagentcore_memory`
   - `aws_bedrock_inference_profile`
   - `aws_bedrock_guardrail`

2. Native Terraform docs also exist in `v6.33.0` for:
   - `aws_bedrockagentcore_browser`
   - `aws_bedrockagentcore_code_interpreter`

3. Repo discrepancy to review:
   - `docs/NOVATION_MATRIX.md` currently marks Browser and Code Interpreter as `cli-required` with note "No native support yet".
   - Provider docs show native resources exist.
   - This may still be an intentional repo decision (stability/non-goal), but the wording "no native support yet" appears stale.

4. Changelog scan supports the freeze-point approach:
   - Bedrock AgentCore resources were introduced and iterated before `v6.33.0`.
   - `v6.30.0` through `v6.33.0` do not show major Bedrock AgentCore resource additions in the scanned sections.

## Files In This Context Pack

- `resource-synthesis-v6.33.0.md`
  - Resource-by-resource summary: purpose, key required inputs, outputs, import IDs, migration notes
- `changelog-synthesis.md`
  - Relevant Terraform AWS provider changelog notes for Bedrock/AgentCore resource maturity
- `sources.md`
  - Primary-source URLs used to build this synthesis

## How To Use This Pack

- Use `docs/NOVATION_MATRIX.md` as the repo migration decision SoT.
- Use `resource-synthesis-v6.33.0.md` to quickly inspect native resource schema shape and import formats.
- Use `changelog-synthesis.md` when deciding whether a provider pin bump is needed for additional migration work.
- If the repo policy conflicts with a newly-available native resource, treat this pack as evidence for review, not as an automatic migration decision.

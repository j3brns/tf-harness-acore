# Sources (Primary + Repo SoT)

Checked on: 2026-02-22

## Repo Source-of-Truth Files

- `docs/NOVATION_MATRIX.md` (repo migration decision matrix)
- `terraform/versions.tf` (provider pin `~> 6.33.0`)

## Terraform AWS Provider (Primary Sources)

Provider changelog:
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/CHANGELOG.md

Provider resource docs used (raw markdown in provider repo, `v6.33.0`):
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrockagentcore_gateway.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrockagentcore_gateway_target.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrockagentcore_agent_runtime.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrockagentcore_memory.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrockagentcore_browser.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrockagentcore_code_interpreter.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrock_inference_profile.html.markdown
- https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.33.0/website/docs/r/bedrock_guardrail.html.markdown

Human-facing registry paths (same resources, versioned provider docs):
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrockagentcore_gateway
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrockagentcore_gateway_target
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrockagentcore_agent_runtime
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrockagentcore_memory
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrockagentcore_browser
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrockagentcore_code_interpreter
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrock_inference_profile
- https://registry.terraform.io/providers/hashicorp/aws/6.33.0/docs/resources/bedrock_guardrail

## AWS Documentation (AWS Knowledge MCP-backed)

- https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/built-in-tools.html
- https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/what-is-bedrock-agentcore.html
- https://aws.amazon.com/bedrock/agentcore/

## Notes

- AWS Knowledge MCP was available and used for AgentCore documentation cross-checks in this synthesis.
- Terraform Registry pages are JS-rendered in some tooling contexts; raw provider repo docs were used for deterministic extraction.


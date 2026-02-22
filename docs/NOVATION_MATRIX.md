# Bedrock AgentCore Terraform Provider Novation Matrix

This document tracks the migration of Bedrock AgentCore resources from CLI-managed (`null_resource` + AWS CLI) to native Terraform resources (`hashicorp/aws` provider).

## 🚀 Status: Workstream A (v0.1.x -> v0.2.0)

- **Target Provider Version**: `v6.33.0`
- **Freeze Point**: Resources marked `cli-required` will not be migrated until native support is verified.

---

## 🛠️ Novation Matrix

| CLI Resource | Module | Terraform Native Resource | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| `null_resource.gateway` | Foundation | `aws_bedrockagentcore_gateway` | **pilot-complete** | Pilot in v6.33.0+ (Issue #18) |
| `null_resource.gateway_target` | Foundation | `aws_bedrockagentcore_gateway_target` | **pilot-complete** | Pilot in v6.33.0+ (Issue #18) |
| `null_resource.workload_identity` | Foundation | (part of `aws_bedrockagentcore_*`) | **native-now** | Implicit or nested in Gateway/Runtime |
| `null_resource.agent_runtime` | Runtime | `aws_bedrockagentcore_agent_runtime` | **native-now** | Full support in v6.32+ |
| `null_resource.agent_memory` | Runtime | `aws_bedrockagentcore_memory` | **native-now** | Full support in v6.33+ |
| `null_resource.inference_profile` | Runtime | `aws_bedrock_inference_profile` | **native-now** | Standard Bedrock resource |
| `null_resource.guardrail` | Governance | `aws_bedrock_guardrail` | **native-now** | Standard Bedrock resource |
| `null_resource.browser` | Tools | -- | **cli-required** | No native support yet |
| `null_resource.code_interpreter` | Tools | -- | **cli-required** | No native support yet |
| `null_resource.policy_engine` | Governance | -- | **cli-required** | AgentCore-specific, pending provider |
| `null_resource.cedar_policies` | Governance | -- | **cli-required** | AgentCore-specific, pending provider |
| `null_resource.custom_evaluator` | Governance | -- | **cli-required** | AgentCore-specific, pending provider |

---

## 🛑 Explicit Non-Goals

1.  **Browser/Code Interpreter**: These resources have complex lifecycle and network configurations that are currently best managed via the CLI bridge to ensure stability.
2.  **Policy Engine/Cedar Policies**: These are undergoing active development in the AgentCore control plane; we will wait for stable native resources.
3.  **Evaluators**: Model-based evaluation logic is highly dynamic; CLI management provides the necessary flexibility for now.

---

## 🎯 Migration Freeze Point

The following provider version is pinned for the duration of Workstream A:

```hcl
# terraform/versions.tf
aws = {
  source  = "hashicorp/aws"
  version = "~> 6.33.0"
}
```

---

## 📅 Revision History

- **2026-02-22**: Initial matrix creation (Issue #17).

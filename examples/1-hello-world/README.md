# Example 1: Minimal Strands Baseline (FAST-Style Parity)

A minimal Strands single-agent demo that provides a small, comparable baseline for chat + tool flow experiments.

## Purpose

This example is intentionally small so you can:
- compare a Strands baseline against future framework demos (for example LangGraph) without extra infrastructure noise
- validate local packaging/runtime behavior quickly
- understand the repo's minimal AgentCore runtime shape before moving to larger examples

## What This Example Shows

- Strands single-agent construction (`Agent(...)`)
- Local tool registration (`@tool`) with small structured outputs
- Bedrock AgentCore runtime entrypoint wiring (`BedrockAgentCoreApp`)
- Deterministic offline demo mode for local smoke checks (no AWS/model credentials required)

## Features Enabled

| Feature | Status | Notes |
|---------|--------|-------|
| Gateway | Disabled | Standalone baseline |
| Code Interpreter | Disabled | Not needed for parity baseline |
| Browser | Disabled | Not needed for parity baseline |
| Memory | Disabled | Stateless baseline |
| Policy Engine | Disabled | Out of scope |
| Evaluations | Disabled | Out of scope |
| Packaging | Enabled | Keeps runtime dependency flow aligned with other examples |
| Observability | Enabled | Basic runtime logs/X-Ray wiring in tfvars |

## Local Run (Offline Smoke)

```bash
cd examples/1-hello-world/agent-code
pip install -e ".[dev]"
python runtime.py --offline --prompt "What is 7 + 5? Also compare this to deepresearch."
```

Notes:
- `--offline` is deterministic and does not call a model.
- `python runtime.py` defaults to offline mode unless `--live` is provided.

## Local Tests (Smoke)

```bash
cd examples/1-hello-world/agent-code
pip install -e ".[dev]"
python -m pytest tests/ -v --tb=short
```

## Optional Live Strands Run

If you have the required model credentials/configuration for Strands, you can try live mode:

```bash
cd examples/1-hello-world/agent-code
python runtime.py --live --prompt "What is 7 + 5?"
```

If live mode fails locally, use `--offline` for smoke validation and continue with deployment/integration work.

## Deploy to AWS

```bash
cd terraform
terraform init
terraform plan -var-file=../examples/1-hello-world/terraform.tfvars
terraform apply -var-file=../examples/1-hello-world/terraform.tfvars
```

## When To Use This vs Other Examples

| Example | Use This When | Notable Tradeoff |
|---------|----------------|------------------|
| `1-hello-world` (this example) | You want a minimal Strands baseline for parity/comparison and fast local smoke checks | No gateway, memory, browser, or multi-agent behavior |
| `3-deepresearch` | You need advanced Strands DeepAgents orchestration, planning, and citations | Much larger dependency/config surface |
| `5-integrated` | You want end-to-end Terraform composition with MCP servers + infrastructure wiring | Infra-focused; not a minimal agent-code baseline |

## Limitations

- Offline mode simulates the chat/tool flow and is meant for reproducible smoke testing, not model quality evaluation.
- The local tools are intentionally simple and do not exercise MCP Gateway or managed AgentCore tools.

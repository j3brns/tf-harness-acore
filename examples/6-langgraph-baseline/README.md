# Example 6: LangGraph Baseline (Minimal)

A minimal LangGraph-based AgentCore runtime example for framework parity with the FAST-style single-agent pattern.

## What This Example Shows

- `LangGraph` state-graph orchestration with deterministic nodes (no external model dependency)
- `bedrock_agentcore.BedrockAgentCoreApp` runtime entrypoint integration
- Structured JSON responses compatible with local smoke testing
- Minimal deployment configuration following the existing example layout

## Features Enabled

| Feature | Status | Notes |
|---------|--------|-------|
| Gateway | Disabled | Runtime-only baseline |
| Code Interpreter | Disabled | Not needed |
| Browser | Disabled | Not needed |
| Memory | Disabled | Stateless demo |
| Policy Engine | Disabled | Not enabled in baseline |
| Evaluations | Disabled | Not enabled in baseline |
| Packaging | **Enabled** | Installs `langgraph` + `bedrock-agentcore` |

## Agent Behavior

The graph executes three small steps:
1. Normalize the incoming prompt
2. Route to a tiny built-in "tool-like" capability summary node
3. Compose a final response with steps and framework metadata

This keeps the example runnable offline while still demonstrating LangGraph orchestration semantics.

## Usage

### Local Run

```bash
cd examples/6-langgraph-baseline/agent-code
pip install -e ".[dev]"
python runtime.py
```

### Local Tests

```bash
cd examples/6-langgraph-baseline/agent-code
python -m pytest tests/ -v --tb=short
```

### Deploy to AWS

```bash
cd terraform
terraform init
terraform plan -var-file=../examples/6-langgraph-baseline/terraform.tfvars
terraform apply -var-file=../examples/6-langgraph-baseline/terraform.tfvars
```

## Purpose and Limitations

- Purpose: small parity/demo baseline for teams evaluating LangGraph vs Strands examples in this repo
- Limitation: no live LLM calls, no MCP gateway, no memory, no browser/code interpreter integration

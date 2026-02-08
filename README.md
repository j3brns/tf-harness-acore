# AWS Bedrock AgentCore Terraform

Production-ready infrastructure for deploying AI agents on AWS Bedrock AgentCore with local-first development and modular architecture.

## Overview

This project provides:

- **Local development first** - Build and test agents in Python before deploying infrastructure
- **Modular Terraform architecture** - 4 independent modules for foundation, tools, runtime, and governance
- **CLI-based provisioning** - Robust infrastructure using AWS CLI + Terraform state management
- **OCDS-compliant packaging** - Two-stage builds with dependency caching
- **Module composition** - Automatic ARN resolution, no hardcoded values
- **CloudWatch monitoring** - Automatic logging and metrics with optional Weave integration

## Architecture

```mermaid
graph TD
    A[agentcore-foundation<br/>Gateway, Identity, Observability] --> B[agentcore-tools<br/>Code Interpreter, Browser]
    A --> C[agentcore-runtime<br/>Runtime, Memory, Packaging]
    C --> D[agentcore-governance<br/>Policy Engine, Evaluations]

    style A fill:#e1f5fe
    style B fill:#f3e5f5
    style C fill:#fff3e0
    style D fill:#e8f5e9
```

**Implementation Note**: Most AWS Bedrock AgentCore resources are provisioned via AWS CLI using `null_resource` + `local-exec` pattern, as they are not yet available in the Terraform AWS provider. IAM roles, CloudWatch logs, and S3 buckets use native Terraform resources.

## Project Structure

```
terraform/
├── modules/
│   ├── agentcore-foundation/   # Gateway, Identity, Observability
│   ├── agentcore-tools/        # Code Interpreter, Browser
│   ├── agentcore-runtime/      # Runtime, Memory, Packaging
│   └── agentcore-governance/   # Policy Engine, Evaluations
├── examples/
│   ├── 1-hello-world/          # Basic S3 explorer
│   ├── 2-gateway-tool/         # MCP gateway with Lambda
│   ├── 3-deepresearch/         # Full research agent
│   ├── 5-integrated/           # Recommended module composition
│   └── mcp-servers/            # Lambda-based MCP tools
├── docs/
│   ├── adr/                    # Architecture Decision Records
│   ├── architecture.md         # System design
│   └── runbooks/               # Operational procedures
├── main.tf                     # Root module
├── variables.tf                # Input variables
├── AGENTS.md                   # Universal AI agent codex (hardlinked)
├── CLAUDE.md                   # → AGENTS.md (hardlink)
├── GEMINI.md                   # → AGENTS.md (hardlink)
└── DEVELOPER_GUIDE.md          # Team onboarding
```

**Note**: `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are hardlinked to the same file. They contain universal development rules and principles that apply to all AI coding agents (Claude, Gemini, etc.). Editing any one file updates all three.

## Prerequisites

- Terraform >= 1.10.0 (for native S3 state locking)
- AWS CLI >= 2.0
- Python 3.12+
- AWS account with Bedrock AgentCore permissions

## Quick Start

### 1. Local Development (No AWS Required)

Start by developing your agent in pure Python:

```bash
# Create agent directory
mkdir my-agent && cd my-agent

# Create runtime.py
cat > runtime.py <<'EOF'
from bedrock_agentcore import BedrockAgentCoreApp

class MyAgent(BedrockAgentCoreApp):
    def invoke(self, event):
        return {
            "status": "success",
            "output": f"Processed: {event.get('input')}"
        }

app = MyAgent()
EOF

# Test locally
python -c "from runtime import app; print(app.invoke({'input': 'test'}))"
```

### 2. Add Dependencies

Create `pyproject.toml` for two-stage OCDS build:

```toml
[project]
name = "my-agent"
version = "1.0.0"
dependencies = [
    "bedrock-agentcore>=1.0.0",
    "requests>=2.28.0"
]
```

### 3. Deploy Infrastructure

```bash
cd terraform

# Initialize
terraform init

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# Deploy
terraform plan
terraform apply
```

### 4. Invoke Agent

```bash
# Get runtime ARN from outputs
RUNTIME_ARN=$(terraform output -raw runtime_arn)

# Invoke
aws bedrock-agentcore-runtime invoke-runtime \
  --runtime-arn "$RUNTIME_ARN" \
  --input '{"input": "Your query here"}' \
  --region us-east-1
```

## Terraform Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `agent_name` | Unique name for the agent |
| `region` | AWS region for deployment |
| `runtime_source_path` | Path to agent source code |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `dev` | Environment name |
| `enable_gateway` | `true` | Enable MCP gateway |
| `enable_code_interpreter` | `true` | Enable Python sandbox |
| `enable_browser` | `false` | Enable web browsing |
| `enable_runtime` | `true` | Enable agent runtime |
| `enable_memory` | `true` | Enable agent memory |
| `enable_evaluations` | `false` | Enable quality evaluation |
| `enable_policy_engine` | `false` | Enable Cedar policies |
| `code_interpreter_network_mode` | `SANDBOX` | Network mode (PUBLIC/SANDBOX/VPC) |
| `log_retention_days` | `30` | CloudWatch log retention |

### Example terraform.tfvars

```hcl
agent_name          = "my-research-agent"
region              = "us-east-1"
environment         = "dev"
runtime_source_path = "../my-agent"

# Enable features
enable_gateway          = true
enable_code_interpreter = true
enable_browser          = true
enable_memory           = true

# MCP targets - Use module composition (recommended)
# See examples/5-integrated/ for pattern
mcp_targets = module.mcp_servers.mcp_targets

tags = {
  Project     = "research-agent"
  Environment = "dev"
}
```

## Examples

### Example 1: Hello World

Basic S3 explorer demonstrating local development:

```bash
# Test locally first
cd examples/1-hello-world/agent-code
python runtime.py

# Then deploy
terraform apply -var-file=examples/1-hello-world/terraform.tfvars
```

### Example 2: Gateway Tool

MCP gateway with Lambda tool for data analysis:

```bash
terraform apply -var-file=examples/2-gateway-tool/terraform.tfvars
```

### Example 3: Deep Research Agent

Full-featured agent using Strands DeepAgents framework:

```bash
terraform apply -var-file=examples/3-deepresearch/terraform.tfvars
```

**Features**: Multi-agent research, internet search, code interpreter, browser, memory, S3 storage

### Example 5: Integrated (Recommended)

Module composition pattern with automatic ARN resolution:

```bash
cd examples/5-integrated
terraform init
terraform apply
```

**Pattern**:
```hcl
module "mcp_servers" {
  source = "../mcp-servers/terraform"
}

module "agentcore" {
  source      = "../../"
  mcp_targets = module.mcp_servers.mcp_targets  # No hardcoded ARNs
}
```

See `examples/5-integrated/README.md` for details.

## Local Development

Test Terraform configurations without AWS:

```bash
# Format check
terraform fmt -check -recursive

# Validate syntax
terraform validate

# Generate plan (no AWS deployment)
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars

# Security scan
checkov -d . --framework terraform

# Lint
tflint --recursive
```

For MCP servers:

```bash
cd examples/mcp-servers

# Local development server
make dev

# Test without AWS
make test-local

# Deploy to AWS
make deploy
```

## Monitoring

### CloudWatch Logs

```bash
# Runtime logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow

# Gateway logs
aws logs tail /aws/bedrock/agentcore/gateway/<agent-name> --follow
```

### Metrics

- Invocations, errors, latency per component
- Evaluation scores and pass/fail rates
- Policy enforcement decisions

### Optional: Weave Integration

Enable enhanced tracing:

```hcl
enable_weave = true
weave_project_name = "my-agent-${var.environment}"
```

Add to Python code:

```python
import weave

class MyAgent(BedrockAgentCoreApp):
    @weave.op()
    def invoke(self, event):
        # Automatically traced
        return self.process(event)
```

## OCDS Two-Stage Build

Dependencies are cached in a layer, code is always fresh:

```
Stage 1: Dependencies (cached)
  pyproject.toml unchanged → Use cached layer

Stage 2: Code (fresh)
  Python files changed → Rebuild package

Result: Fast iteration on code changes
```

Hash-based triggers ensure rebuilds only when needed. See `examples/mcp-servers/terraform/packaging.tf` for implementation.

## Security

- **Encryption**: AWS-managed (SSE-S3) by default, optional customer-managed KMS
- **IAM**: Least privilege roles with granular permissions
- **Policy Engine**: Cedar policies for access control
- **Network**: VPC isolation support for Code Interpreter and Browser

See `docs/adr/0008-aws-managed-encryption.md` for encryption rationale.

## State Management

Recommended S3 backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-state-prod"
    key          = "bedrock-agentcore/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true  # Native S3 locking (Terraform 1.10+)
  }
}
```

## Cost Estimation

Typical monthly costs per agent:

| Component | Cost |
|-----------|------|
| Gateway | Free tier |
| Code Interpreter | $1-10 |
| Browser | $0.50-5 |
| CloudWatch Logs | $0.50-5 |
| S3 Storage | $0.02/GB |
| Weave (optional) | $5-10 |
| **Total** | **~$3-35** |

Varies by usage and region.

## Documentation

- **[IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)** - Comprehensive test & validation plan with phases
- **[DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md)** - Team onboarding and common tasks
- **[AGENTS.md](./AGENTS.md)** / **[CLAUDE.md](./CLAUDE.md)** / **[GEMINI.md](./GEMINI.md)** - Universal AI agent development rules (hardlinked files - same content)
- **[docs/architecture.md](./docs/architecture.md)** - System design and data flows
- **[docs/adr/](./docs/adr/)** - Architecture Decision Records
- **[docs/runbooks/](./docs/runbooks/)** - Operational procedures
- **[docs/WIF_SETUP.md](./docs/WIF_SETUP.md)** - GitLab CI/CD with Web Identity Federation

**Note on Agent Files**: `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are hardlinked (same file, different names). They serve as a Universal Codex containing development rules, security requirements, and architectural patterns that apply to all AI coding agents. Claude Code auto-loads `CLAUDE.md`, while other AI assistants may reference `AGENTS.md` or `GEMINI.md`.

## Troubleshooting

### CLI Command Fails

If `bedrock-agentcore-control` commands error:

1. Update AWS CLI: `aws --version` (requires >= 2.0)
2. Check IAM permissions
3. Verify region supports Bedrock AgentCore
4. Review CloudWatch logs

### Packaging Fails

1. Verify source path exists
2. Check `pyproject.toml` syntax
3. Test pip install locally
4. Review `.terraform/` directory

### No Hardcoded ARNs Error

If you see placeholder ARNs (123456789012):

- Use module composition pattern (see Example 5)
- Use data sources: `data.aws_lambda_function.existing.arn`
- Never hardcode account IDs or regions

See `CLAUDE.md` Rule 1.7 for details.

## Development Workflow

```mermaid
graph LR
    A[Local Python Dev] --> B[Add Dependencies]
    B --> C[Terraform Deploy]
    C --> D[Monitor & Iterate]

    style A fill:#e1f5fe
    style B fill:#fff3e0
    style C fill:#e8f5e9
    style D fill:#fce4ec
```

1. **Local**: Develop and test in Python (no AWS)
2. **Dependencies**: Add `pyproject.toml` for OCDS packaging
3. **Deploy**: Run `terraform apply` to provision infrastructure
4. **Monitor**: View logs in CloudWatch, iterate on code

## Contributing

See [DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md) for:
- Common development tasks
- Module architecture rules
- Security requirements
- Testing procedures

## References

- [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cedar Policy Language](https://www.cedarpolicy.com/)
- [Strands DeepAgents Framework](https://strandsagents.com/)

## License

MIT - See LICENSE file for details.

# Bedrock AgentCore Terraform // Production-Ready AI Infrastructure

Deploy, secure, and scale production AI agents on AWS Bedrock with a **local-first DX**, **Zero-Trust security**, and **Instant Hot-Reload**.

## Core Engineering Principles

Bedrock AgentCore is a comprehensive framework designed for teams deploying AI Agents in production environments. It addresses several critical challenges in AI infrastructure engineering:

### 1. The Bridge Pattern (AWS CLI Integration)
We utilize a stateful "Bridge" pattern to manage the lifecycle of newer Bedrock features. By wrapping the AWS CLI in `null_resource` provisioners and using **SSM Parameter Store** to persist resource IDs, we provide Day 0 access to new models, inference profiles, and guardrails with production-grade lifecycle safety.

### 2. OCDS: Optimized Packaging
**Optimized Code/Dependency Separation (OCDS)** is our specialized build protocol. 
*   **Architecture Aware**: Automatically detects and builds for **x86_64** or **ARM64 (Graviton)** via the `lambda_architecture` variable, optimizing for price-performance.
*   **Layered Hashing**: By hashing `pyproject.toml` independently of code files, we ensure that heavy dependency layers are only rebuilt when necessary.
*   **Hardened Security**: The packaging engine strictly excludes local sensitive files (`.env`, `.tfvars`) and development artifacts (`tests/`, `venv/`) from production archives.

### 3. Modular Regional Topology
The framework supports granular regional splitting out of the box. You can deploy the **Control Plane**, **BFF**, and **Models** in different regions (e.g., for data residency or availability constraints) while maintaining seamless integration through automated wiring.

### 4. Zero-Trust Security
Our security model assumes the frontend may be compromised:
*   **Token Handler Pattern (ADR 0011):** The Serverless BFF (Backend-for-Frontend) ensures that OIDC tokens are exchanged server-side and never reach the browser, preventing XSS-based token theft.
*   **Hardened Session Management:** Uses **Secure, HttpOnly, and SameSite=Strict** cookies for session identification.
*   **Mandatory Server-Side Validation:** A Lambda Authorizer validates every API request against DynamoDB sessions before injecting identity context into the backend.
*   **Audit Logging:** Implements detailed audit logging for all proxy interactions to maintain compliance standards.

## Framework Features

*   ⚡ **Fast OCDS Builds**: Instant updates for agent logic without full dependency reinstalls.
*   🖥️ **Interactive CLI Terminal**: A dedicated terminal interface for real-time observability, log tailing, and remote management.
*   🛡️ **ABAC & Cedar Support**: Zero-trust security using Attribute-Based Access Control and Cedar policy enforcement.
*   🔐 **Credential-Level Isolation**: Dynamic IAM Session Policies physically restrict agent access per-tenant at the credential layer.
*   🚦 **Resilience Toggles**: Pre-configured Lambda concurrency limits and WAF IP-rate limiting to protect against account-wide DOS.
*   🚀 **Enterprise Templates**: Scaffold fully compliant, production-ready agents using `copier`.

## Architecture

### Logic & Modules
```mermaid
graph TD
    A[agentcore-foundation<br/>Gateway, Identity, Observability] --> B[agentcore-tools<br/>Code Interpreter, Browser]
    A --> C[agentcore-runtime<br/>Runtime, Memory, Packaging]
    C --> D[agentcore-governance<br/>Policy Engine, Evaluations]
    A --> E[agentcore-bff<br/>OIDC, Proxy, SPA]

    style A fill:#e1f5fe
    style B fill:#f3e5f5
    style C fill:#fff3e0
    style D fill:#e8f5e9
    style E fill:#fff9c4
```

### Physical Infrastructure
```mermaid
flowchart TD
    subgraph North[Entry Point: AppID]
        APIGW[API Gateway]
    end

    subgraph Middle[Identity Layer: TenantID]
        LAuthorizer[Lambda Authorizer]
        DDB[(DynamoDB Sessions<br/>PK: APP#AppID#TENANT#TenantID)]
    end

    subgraph South[Compute Layer: AgentName]
        LProxy[Proxy Lambda]
        BGateway[Bedrock Gateway]
        BRuntime[Bedrock Runtime]
        BSandbox[Code Interpreter<br/>x86_64 / arm64]
    end

    subgraph Storage[Partitioned Persistence]
        S3Memory[S3 Memory<br/>/AppID/TenantID/AgentName/]
        S3Deploy[S3 Deploy]
    end

    Browser[Browser] -- "AppID Context" --> North
    North --> LAuthorizer
    LAuthorizer <--> DDB
    North -- "Validated Identity" --> LProxy
    LProxy -- "x-tenant-id / x-app-id" --> BGateway
    BGateway --> BRuntime
    BRuntime <--> S3Memory
    BRuntime <--> S3Deploy
```

**Implementation Note**: Most AWS Bedrock AgentCore resources are provisioned via the mandatory **CLI Pattern** (AWS CLI + Terraform State) to bridge provider gaps while maintaining strict IaC principles. Native resources (IAM, S3, CloudWatch) use standard Terraform.

## Lifecycle (Local → Cloud → Local)

```mermaid
stateDiagram-v2
    [*] --> LocalDev: edit tool or agent code
    LocalDev --> LocalTest: run local MCP server
    LocalTest --> Package: deps and code packaging
    Package --> Deploy: terraform apply
    Deploy --> Observe: CloudWatch and X-Ray
    Observe --> LocalDev: feedback loop
```

## Informal Flow (Local → Cloud)

```mermaid
flowchart LR
  subgraph Phase1[Phase 1: Local Build]
    A[Write agent and tool code] --> B[Run locally]
    B --> C[Quick checks and tests]
  end

  subgraph Phase2[Phase 2: Observability]
    D[Enable telemetry] --> E[Weave or OTEL backend]
  end

  subgraph Phase3[Phase 3: Infra and Deploy]
    F[Terraform plan and apply] --> G[AgentCore runtime and gateway]
    G --> H[MCP tools - Lambda]
  end

  subgraph Phase4[Phase 4: Operate]
    I[User traffic] --> J[Runtime executes]
    J --> K[Logs and traces]
    K --> L[Fix and iterate]
  end

  C --> F
  B --> D
  G --> J
  E --> K
  L --> A
```

## Project Structure

```
repo-root/
├── terraform/
│   ├── modules/
│   │   ├── agentcore-foundation/   # Gateway, Identity, Observability
│   │   ├── agentcore-tools/        # Code Interpreter, Browser
│   │   ├── agentcore-runtime/      # Runtime, Memory, Packaging
│   │   └── agentcore-governance/   # Policy Engine, Evaluations
│   ├── scripts/                    # Validation helpers
│   ├── tests/                      # Terraform-focused tests
│   ├── main.tf                     # Root module
│   ├── variables.tf                # Input variables
│   └── terraform.tfvars.example    # Example config
├── examples/
│   ├── 1-hello-world/              # Basic S3 explorer
│   ├── 2-gateway-tool/             # MCP gateway with Lambda
│   ├── 3-deepresearch/             # Full research agent
│   ├── 5-integrated/               # Recommended module composition
│   └── mcp-servers/                # Lambda-based MCP tools
├── docs/
│   ├── adr/                        # Architecture Decision Records
│   ├── architecture.md             # System design
│   └── runbooks/                   # Operational procedures
├── AGENTS.md                       # Universal AI agent codex (hardlinked)
├── CLAUDE.md                       # → AGENTS.md (hardlink)
├── GEMINI.md                       # → AGENTS.md (hardlink)
└── DEVELOPER_GUIDE.md              # Team onboarding
```

**Note**: `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are hardlinked to the same file. They contain universal development rules and principles that apply to all AI coding agents (Claude, Gemini, etc.). Editing any one file updates all three.

## Prerequisites

- Terraform 1.14.4 (see `terraform/.terraform-version`)
- AWS CLI >= 2.0
- Python 3.12+
- AWS account with Bedrock AgentCore permissions

## Quick Start

### 1. Scaffold with Template

Don't start from scratch. Use our enterprise `copier` template to generate a fully compliant agent project.

```bash
# Install copier
pip install copier

# Generate project
copier copy --trust templates/agent-project my-agent
cd my-agent
```

### 2. Local Development (No AWS Required)

Start by developing your agent in pure Python:

```bash
# Test locally
cd agent-code
python runtime.py
```

### 3. Add Dependencies

Edit `pyproject.toml` to add libraries. The OCDS build system will automatically cache them.

```toml
[project]
name = "my-agent"
version = "1.0.0"
dependencies = [
    "bedrock-agentcore>=1.0.0",
    "requests>=2.28.0"
]
```

### 4. Deploy Infrastructure

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
| `agentcore_region` | `""` | Optional AgentCore control-plane region override (defaults to `region`) |
| `bedrock_region` | `""` | Optional Bedrock model/guardrail/inference profile region override (defaults to `agentcore_region`) |
| `bff_region` | `""` | Optional BFF/API Gateway region override (defaults to `agentcore_region`) |
| `bff_agentcore_runtime_arn` | `""` | Optional runtime ARN for BFF (required if enable_bff=true and enable_runtime=false) |
| `enable_gateway` | `true` | Enable MCP gateway |
| `enable_code_interpreter` | `true` | Enable Python sandbox |
| `enable_browser` | `false` | Enable web browsing |
| `enable_runtime` | `true` | Enable agent runtime |
| `enable_memory` | `true` | Enable agent memory |
| `enable_evaluations` | `false` | Enable quality evaluation |
| `enable_policy_engine` | `false` | Enable Cedar policies |
| `code_interpreter_network_mode` | `SANDBOX` | Network mode (PUBLIC/SANDBOX/VPC) |
| `log_retention_days` | `30` | CloudWatch log retention |

Region splits are optional. If you need API Gateway/BFF in a different region than AgentCore, set `bff_region`. If you need Bedrock models in a different region, set `bedrock_region`. If you enable the BFF without creating a runtime in this module, set `bff_agentcore_runtime_arn`.

### Example terraform.tfvars

```hcl
agent_name          = "my-research-agent"
region              = "us-east-1"
environment         = "dev"
runtime_source_path = "../my-agent"
agentcore_region    = ""
bedrock_region      = ""
bff_region          = ""
bff_agentcore_runtime_arn = ""

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

## Monitoring & Management

### The AgentCore Terminal
Launch the interactive terminal for real-time monitoring and remote management of your deployed agents:

```bash
# Launch the Terminal (Auto-discovers region and ID)
python terraform/scripts/acore_debug.py
```

*   📡 **Live Log Tailing**: Integrated CloudWatch log streaming with near-zero latency.
*   🚦 **System Metrics**: Real-time monitoring of authorizer decisions and model latency.
*   🔄 **Remote Update**: Trigger OCDS Hot-Reloads directly from the terminal.

## Serverless BFF & Web UI

The Backend-for-Frontend module provides a secure web interface for agent interaction:

*   🖥️ **Web Interface**: A responsive SPA (Single Page Application) for direct user interaction.
*   🛡️ **Secure Auth**: Pure serverless OIDC implementation using the Token Handler pattern and PKCE.
*   🕵️ **Compliance Ready**: Detailed logging of all proxy payloads for audit and compliance reporting.

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

- **[docs/archive/IMPLEMENTATION_PLAN.md](./docs/archive/IMPLEMENTATION_PLAN.md)** - Historical test & validation plan (archived)
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
   
 
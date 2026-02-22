# Developer Guide - Bedrock AgentCore Terraform

## Welcome

This guide will get you from zero to deploying agents in under 30 minutes.

## Prerequisites

### Required
- Git installed
- Terraform >= 1.5.0 (use `terraform/.terraform-version` with tfenv)
- AWS CLI configured
- Python 3.12+
- Text editor (VS Code recommended)

### Optional
- Docker (for local testing)
- Go 1.20+ (for Terratest)
- pre-commit (`uv tool install pre-commit` recommended on Windows)
- TFLint
- Checkov

## Quick Start (5 Minutes)

```bash
# 1. Clone repository
git clone <repo-url>
cd <repo-name>
cd terraform

# 2. Install pre-commit hooks (optional but recommended)
uv tool install pre-commit
pre-commit install

# 3. Validate everything works
terraform init -backend=false
terraform validate
terraform fmt -check

# 4. Run security scan
checkov -d . --framework terraform --compact --config-file .checkov.yaml

# 5. Test with example
terraform plan \
  -var-file=../examples/1-hello-world/terraform.tfvars \
  -var="app_id=dev-sandbox" \
  -var="lambda_architecture=arm64"
```

If all commands succeed, you're ready to develop!

## Versioning

- Canonical repo version lives in `VERSION`.
- Current release line is `0.1.x`.
- Release tags are immutable and formatted as `vMAJOR.MINOR.PATCH` (example `v0.1.0`).
- When bumping version, update `VERSION` and `CHANGELOG.md` in the same commit.
- Push release refs to both remotes: `origin` (GitHub) and `gitlab` (GitLab).

## Core Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `agent_name` | Internal physical agent identity (immutable; use suffix pattern like `research-agent-core-a1b2`). | - |
| `app_id` | Human-facing application alias / logical boundary (North Anchor). | `${agent_name}` |
| `allow_legacy_agent_name` | Temporary migration escape hatch for an existing deployed legacy `agent_name`. | `false` |
| `lambda_architecture` | Compute architecture (`x86_64` or `arm64`). | `x86_64` |
| `environment` | Deployment stage (`dev`, `staging`, `prod`). | `dev` |

## Development Workflow

### Making Changes

```bash
# 1. Make your changes
# Edit files...

# 2. Validate locally (NO AWS needed)
cd terraform
terraform fmt -recursive
terraform validate
terraform plan -backend=false

# 3. Security scan
checkov -d . --framework terraform --compact --config-file .checkov.yaml

# 4. Commit (pre-commit hooks run automatically)
git add .
git commit -m "feat: add new capability"

# 5. Push to main
git push origin main
```

### Local Testing (No AWS Required)

```bash
# Format check
cd terraform
terraform fmt -check -recursive

# Generate policy and tag conformance report (Inventory + Governance)
make policy-report

# Generate all documentation (including MCP Tools OpenAPI + typed client)
make docs
```

#### MCP Tools OpenAPI + Typed Client Generation

The project includes a script to automatically generate an OpenAPI 3.1.0 specification from the MCP tools registry defined in `examples/mcp-servers/*/handler.py`.

To generate or update the OpenAPI spec:

```bash
make generate-openapi
```

To generate the typed TypeScript client from that OpenAPI artifact:

```bash
make generate-openapi-client
```

To verify the committed typed client matches the current OpenAPI spec (drift check used in CI):

```bash
make check-openapi-client
```

Generated artifacts:
- `docs/api/mcp-tools-v1.openapi.json`
- `docs/api/mcp-tools-v1.client.ts`

These artifacts can be used by the Web UI and integrators to consume a consistent tool-calling contract without ad hoc request code.

#### Streaming Load Tester (Issue #32)

For deployed BFF environments, use the automated streaming load tester to validate the 15-minute (900s) response-streaming path and capture evidence for issue/PR closeout:

```bash
# Direct API Gateway invoke URL (terraform output agentcore_bff_api_url + /chat)
make streaming-load-test ARGS='--session-cookie tenant-a:session-123 --duration-seconds 900 --json-summary --verbose'

# CloudFront path (/api/chat) instead of direct API Gateway
make streaming-load-test ARGS='--use-spa-url --session-cookie tenant-a:session-123 --duration-seconds 900'
```

Notes:
- The tester sends a default prompt that instructs a long-running mock tool to emit heartbeat updates.
- Override with `--prompt "..."` if your test agent uses a different mock tool contract.
- PASS criteria are configurable (`--min-stream-seconds`, `--min-delta-events`, `--allow-non-ndjson`).
- If Terraform outputs are unavailable in the current worktree, pass `--url https://.../chat` explicitly.

#### Frontend Component Library (React + Tailwind, No Bundler)

The SPA template and the integrated example now ship with a reusable frontend component library:

- `templates/agent-project/frontend/components.js`
- `examples/5-integrated/frontend/components.js`

The library is intentionally static-hosting friendly:

- React is loaded via browser ES modules (no Node build step required)
- Tailwind is loaded via CDN
- Components are plain reusable blocks (`AppShell`, `Panel`, `MetricCard`, `Transcript`, `Timeline`, `ToolCatalog`, etc.)

To customize a specialized dashboard, compose panels in `frontend/app.js` and keep shared primitives in `frontend/components.js`. The example app will try to load `docs/api/mcp-tools-v1.openapi.json` so issue `#33` OpenAPI output can drive tool panels, and issue `#51` adds a generated typed client at `docs/api/mcp-tools-v1.client.ts` for integrator/frontend SDK usage.

# Syntax validation
terraform validate

# Generate plan (dry-run)
terraform plan -backend=false -var-file=../examples/1-hello-world/terraform.tfvars

# Security scan
checkov -d . --framework terraform --compact --config-file .checkov.yaml

# Lint
tflint --recursive

# Governance conformance (tags + wildcard policy exceptions)
make policy-report

# Artifacts:
# - docs/POLICY_CONFORMANCE_REPORT.md
```

**Key Point**: You can validate everything locally without an AWS account!

### Windows Notes (pre-commit + Terraform hooks)
Terraform pre-commit hooks run via bash. On Windows:
- For full checks, run `pre-commit` from **Git Bash or WSL**.
- For a Windows-native minimal check, use `validate_windows.bat` (runs `terraform fmt` + `pre-commit` with Terraform hooks skipped).

## Core Engineering Patterns

### OCDS (Optimized Code/Dependency Separation)

AgentCore uses a two-stage build process to ensure instant deployments:
1.  **Stage 1 (Deps)**: Layers `pyproject.toml` into a dependency cache.
2.  **Stage 2 (Code)**: Packages your agent logic.

**Architecture Support**:
You can target AWS Graviton (ARM64) for lower latency and cost by setting `lambda_architecture = "arm64"`. The OCDS engine will automatically fetch the correct Linux binaries.

### Multi-Tenancy (North-South Join)
Every interaction is anchored by the North-South join hierarchy:
- **North (AppID)**: The logical boundary. In development, use unique values to isolate your work.
- **Middle (TenantID)**: The unit of data ownership, extracted from the OIDC token.
- **South (AgentName)**: The internal physical compute identity (keep stable; use `app_id` for human-facing labels).

## Project Structure

```
repo-root/
+-- terraform/            # Terraform root module + tooling
|   +-- modules/           # Core modules (require approval for changes)
|   |   +-- agentcore-foundation/
|   |   +-- agentcore-tools/
|   |   +-- agentcore-runtime/
|   |   +-- agentcore-governance/
|   |
|   +-- scripts/           # Helper scripts
|   |   +-- validate_examples.sh
|   |
|   +-- tests/             # Test suite
|   |   +-- validation/
|   |   +-- security/
|   |
|   +-- main.tf            # Module composition
|   +-- variables.tf       # Input variables
|   +-- outputs.tf         # Output values
|   +-- versions.tf        # Provider versions
|   +-- .terraform-version # Pinned Terraform version
|
+-- examples/             # Example agents
|   +-- 1-hello-world/    # Basic S3 explorer agent
|   +-- 2-gateway-tool/   # MCP gateway with Titanic analysis
|   +-- 3-deepresearch/   # Full Strands DeepAgents implementation
|   +-- 4-research/       # Simplified research agent
|
+-- docs/                 # Documentation
|   +-- adr/              # Architecture Decision Records
|   +-- architecture.md   # System architecture
|   +-- runbooks/         # Operational runbooks
|
+-- CLAUDE.md             # AI agent development rules
+-- DEVELOPER_GUIDE.md    # This file
+-- README.md             # User documentation
```

## Common Tasks

### Task 1: Create a New Example Agent

```bash
# 1. Scaffold in scratch using Copier (non-interactive)
copier copy --force --trust \
  --data agent_name=my-agent-core-a1b2 \
  --data app_id=my-agent \
  --data region=us-east-1 \
  --data environment=dev \
  --data enable_bff=true \
  templates/agent-project .scratch/my-agent

# 2. Validate generated agent code
cd .scratch/my-agent/agent-code
python3 -m pip install -e ".[dev]"
python3 -m pytest tests/ -v --tb=short

# 3. Validate generated Terraform
cd ../terraform
terraform init -backend=false
terraform validate
```

### Task 2: Add a New Variable

```hcl
# 1. Add to module's variables.tf with validation
variable "my_setting" {
  description = "My new setting"
  type        = string
  default     = "default-value"

  validation {
    condition     = length(var.my_setting) > 0
    error_message = "Value must not be empty."
  }
}

# 2. Use in module resources
# terraform/modules/agentcore-foundation/gateway.tf
resource "null_resource" "gateway" {
  triggers = {
    name = var.my_setting
  }
  # See Rule 3.1 in AGENTS.md for the full pattern
}

# 3. Add to root variables.tf (terraform/variables.tf)
variable "my_setting" {
  description = "My new setting"
  type        = string
  default     = "default-value"
}

# 4. Pass to module in main.tf (terraform/main.tf)
module "agentcore_foundation" {
  source = "./modules/agentcore-foundation"
  my_setting = var.my_setting
}

# 5. Test
terraform validate
```

### Task 3: Fix Security Issue

```bash
# 1. Run Checkov to identify issues
checkov -d . --framework terraform

# 2. Review findings and fix
# Example: Replace wildcard resource with specific ARN

# 3. Re-run Checkov
checkov -d . --framework terraform

# 4. Verify fix
terraform validate
terraform plan
```

## Module Guide

### Foundation Module

Controls: Gateway, Identity, Observability

```hcl
# Enable/disable features
enable_gateway       = true
enable_identity      = false
enable_observability = true
enable_xray          = true

# Gateway configuration
gateway_name        = "my-gateway"
gateway_search_type = "HYBRID"  # or "SEMANTIC"

# MCP targets (Lambda functions)
mcp_targets = {
  my_tool = {
    name       = "my-tool"
    lambda_arn = "arn:aws:lambda:us-east-1:ACCOUNT:function:my-mcp"
  }
}
```

Cross-account gateway target pattern (least privilege):
- The foundation module scopes gateway-role `lambda:InvokeFunction` to the exact `mcp_targets[*].lambda_arn` values.
- If the target Lambda is in another account, add a resource-based policy on that Lambda for the gateway service role ARN (`agentcore_gateway_role_arn` output from the root module).
- If BFF invokes a runtime in another account, set both `bff_agentcore_runtime_arn` and `bff_agentcore_runtime_role_arn`.

### Tools Module

Controls: Code Interpreter, Browser

```hcl
# Code interpreter
enable_code_interpreter       = true
code_interpreter_network_mode = "SANDBOX"  # PUBLIC, SANDBOX, VPC

# Browser
enable_browser       = true
browser_network_mode = "SANDBOX"
```

### Runtime Module

Controls: Runtime, Memory, Packaging

```hcl
# Runtime
enable_runtime      = true
runtime_source_path = "./agent-code"
runtime_entry_file  = "runtime.py"

# Memory
enable_memory = true
memory_type   = "BOTH"  # SHORT_TERM, LONG_TERM, BOTH

# Packaging
enable_packaging = true
python_version   = "3.12"
```

### Governance Module

Controls: Policy Engine, Evaluations

```hcl
# Policy engine
enable_policy_engine = true
cedar_policy_files = {
  pii = "./policies/pii-protection.cedar"
}

# Evaluations
enable_evaluations = true
evaluation_type    = "REASONING"  # TOOL_CALL, REASONING, RESPONSE, ALL
evaluator_model_id = "anthropic.claude-sonnet-4-5"
```

## Testing Your Changes

### Level 1: Local Validation (Always Run)

```bash
# Quick validation (30 seconds)
terraform fmt -check
terraform validate
terraform plan -backend=false -var-file=examples/1-hello-world/terraform.tfvars
```

### Level 2: Security Scan (Before Commit)

```bash
# Security check (1 minute)
checkov -d . --framework terraform --compact
tflint --recursive
```

### Level 3: Full Test Suite

```bash
# Complete tests (5 minutes)
make test-all

# Or individually:
make test-validate
make test-security
make test-frontend
```

## Debugging

### Common Issues

#### "terraform: command not found"
```bash
# Install Terraform
# macOS
brew install terraform

# Or use tfenv
brew install tfenv
tfenv install 1.5.7
tfenv use 1.5.7
```

#### "Error: Module not found"
```bash
# Initialize Terraform
terraform init -backend=false
```

#### "Checkov failed with critical issues"
```bash
# See detailed output
checkov -d . --framework terraform

# Fix issues, then re-run
```

#### "Pre-commit hooks failing"
```bash
# Run manually to see errors
pre-commit run --all-files

# Fix issues, then retry commit
```

## CI Pipeline

### GitHub Actions (validation only)
- Runs docs/tests gate, Terraform fmt/validate, TFLint, Checkov, and example validation.
- Uses `terraform init -backend=false` on the runner (local only, no AWS).
- Uses shared GitHub Actions for Terraform, TFLint, and Checkov setup plus caching.
- Caches Terraform plugins, TFLint plugins, and pip downloads to speed CI runs.
- No deployments run in GitHub Actions.

### GitLab CI (deployment pipeline)

### Pipeline Stages

```
validate -> lint -> test -> plan:dev -> promote:dev -> deploy:dev -> smoke-test:dev -> promote:test -> plan:test -> deploy:test -> smoke-test:test -> gate:prod-from-test -> plan:prod -> deploy:prod -> smoke-test:prod
  (auto)    (auto)  (auto)    (auto)       (manual)       (auto)         (auto)              (manual)      (auto)       (manual)      (auto)              (auto)                 (auto)      (manual)      (auto)
```

### Triggering Deployments

**Dev**: Planned on push to `main`, deploy gated by manual promotion
```bash
git checkout main
git push origin main
git push gitlab main
# In GitLab, run promote:dev to allow deploy:dev.
# deploy:dev -> smoke-test:dev then continue automatically.
```

**Test**: Manual/API pipeline from `main` only
```bash
# Pushes do not create test-environment jobs.
# In GitLab, click "Run pipeline" on main (or trigger via API), then run promote:test.
# promote:test requires deploy:dev + smoke-test:dev success in the same pipeline.
# plan:test -> deploy:test -> smoke-test:test are chained behind promote:test.
```

**Prod**: Manual from tag
```bash
# Tag the same commit SHA that passed main deploy:test + smoke-test:test
git tag v0.1.0
git push origin v0.1.0
git push gitlab v0.1.0
# gate:prod-from-test must pass, then trigger deploy-prod manually
```

## Best Practices

### DO
- Run `make preflight-session` at session start and before commit/push
- Use `make worktree` to create/resume linked worktrees with enforced naming + preflight
- Run `terraform validate` before every commit
- Use pre-commit hooks
- Test examples after module changes
- Add validation to variables
- Use descriptive commit messages
- Keep changes focused (one logical change per commit)
- Document decisions in ADRs
- Update docs when changing code
- Close issues with a comprehensive summary comment (changes, validation, outcomes)

### DON'T
- Use `Resource = "*"` in IAM policies
- Suppress errors with `|| true`
- Skip validation before pushing
- Use placeholder ARNs (123456789012)
- Make changes without running Checkov
- Forget to update documentation

## Cheat Sheet

```bash
# Validate everything
terraform fmt -check && terraform validate

# Format code
terraform fmt -recursive

# Security scan
checkov -d . --framework terraform --compact

# Test example
terraform plan -var-file=examples/1-hello-world/terraform.tfvars

# View outputs
terraform output

# Get help
terraform --help
```

## Getting Help

1. Check `CLAUDE.md` - AI agent development rules
2. Check `docs/architecture.md` - System design
3. Check `docs/adr/` - Architecture decisions
4. Create GitLab issue for bugs/features

## Next Steps

1. Complete quick start
2. Read `CLAUDE.md`
3. Review `examples/`
4. Try modifying an example
5. Create your first release tag (`v0.1.x`) after validation
6. Deploy to dev

Welcome to the team!

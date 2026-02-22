# Example 5: Integrated MCP Servers + AgentCore

This example demonstrates the **recommended pattern** for deploying AgentCore agents with MCP servers:

1. MCP servers deployed as a Terraform submodule
2. ARNs automatically resolved - no hardcoding
3. Single `terraform apply` deploys everything

## Why This Pattern?

- **No hardcoded ARNs** - Region and account ID are automatic
- **Single deployment** - MCP servers + Agent in one command
- **Proper dependencies** - Agent waits for MCP servers to be ready
- **Easy updates** - Change MCP server code, redeploy, agent uses new version

## Quick Start

```bash
cd examples/5-integrated
terraform init
terraform apply
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Terraform Configuration                      │
│                                                                  │
│  ┌──────────────────────┐      ┌──────────────────────────────┐│
│  │  module.mcp_servers  │      │     module.agentcore         ││
│  │                      │      │                              ││
│  │  ┌────────────────┐  │      │  ┌──────────────────────┐   ││
│  │  │ s3-tools       │──┼──────┼─▶│ Gateway              │   ││
│  │  │ Lambda         │  │ ARN  │  │   mcp_targets = {    │   ││
│  │  └────────────────┘  │      │  │     s3_tools: ...    │   ││
│  │                      │      │  │     titanic: ...     │   ││
│  │  ┌────────────────┐  │      │  │   }                  │   ││
│  │  │ titanic-data   │──┼──────┼─▶│                      │   ││
│  │  │ Lambda         │  │ ARN  │  └──────────────────────┘   ││
│  │  └────────────────┘  │      │                              ││
│  └──────────────────────┘      │  ┌──────────────────────┐   ││
│                                │  │ Runtime              │   ││
│                                │  │   agent-code/        │   ││
│                                │  └──────────────────────┘   ││
│                                └──────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Key Code Pattern

```hcl
# Step 1: Deploy MCP servers
module "mcp_servers" {
  source = "../mcp-servers/terraform"
  environment = var.environment
}

# Step 2: Use outputs in AgentCore config
module "agentcore" {
  source = "../../"

  # Automatic ARN resolution!
  mcp_targets = module.mcp_servers.mcp_targets

  depends_on = [module.mcp_servers]
}
```

## What Gets Deployed

| Resource | Purpose |
|----------|---------|
| `agentcore-mcp-s3-tools-dev` | Lambda for S3 operations |
| `agentcore-mcp-titanic-data-dev` | Lambda for Titanic dataset |
| AgentCore Gateway | MCP protocol endpoint |
| AgentCore Runtime | Agent execution |
| Code Interpreter | Python sandbox |
| CloudWatch Logs | Observability |

## Customization

Edit `main.tf` to:

- Add more MCP servers to `module.mcp_servers`
- Change agent capabilities (enable browser, memory, etc.)
- Modify runtime configuration

### Frontend Dashboard Customization

The example frontend now uses a reusable React/Tailwind component library (no bundler required):

- `frontend/components.js` contains reusable primitives (`AppShell`, `Panel`, `MetricCard`, `Transcript`, `Timeline`, `ToolCatalog`, `JsonPreview`)
- `frontend/app.js` composes those primitives into an operator dashboard

To build a specialized dashboard, keep shared UI blocks in `frontend/components.js` and swap panel composition/data wiring in `frontend/app.js`. The app will also try to load `docs/api/mcp-tools-v1.openapi.json` to populate a tool catalog panel from generated OpenAPI metadata.

## Testing

```bash
# Check deployed resources
terraform output

# View MCP server ARNs (automatically generated!)
terraform output mcp_server_arns

# Test MCP server directly
aws lambda invoke \
  --function-name agentcore-mcp-titanic-data-dev \
  --payload '{"tool": "get_statistics", "parameters": {}}' \
  response.json
```

## Cleanup

```bash
terraform destroy
```

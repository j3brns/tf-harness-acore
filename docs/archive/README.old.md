# Generalized AWS Bedrock AgentCore Terraform Architecture

A comprehensive, modular Terraform implementation for deploying AWS Bedrock AgentCore agents with support for all 9 core features: Gateway (MCP), Identity, Observability, Code Interpreter, Browser, Runtime, Memory, Policy Engine, and Evaluations.

## Overview

This architecture provides:

- **100% Terraform-native resources** for Gateway, Identity, Code Interpreter, Browser, and Observability (6/13 resources)
- **CLI-based patterns** for Runtime, Memory, Policy Engine, and Evaluations (7/13 resources) using `null_resource` + `local-exec`
- **Complete backward compatibility** with existing agent implementations
- **Feature-independent** modules - enable/disable each feature independently
- **OCDS compliance** - two-stage build process, hash-based triggers, deployment auditability
- **Production-ready** - KMS encryption, VPC support, IAM least privilege, comprehensive logging

## Architecture

### Module Structure

```
terraform/
├── modules/
│   ├── agentcore-foundation/       # Gateway, Identity, Observability
│   ├── agentcore-tools/            # Code Interpreter, Browser
│   ├── agentcore-runtime/          # Runtime, Memory, Packaging
│   └── agentcore-governance/       # Policy Engine, Evaluations
├── examples/                       # Example configurations
├── main.tf                         # Root orchestration
├── variables.tf                    # Root variables
├── outputs.tf                      # Root outputs
└── versions.tf                     # Provider configuration
```

### Dependency Graph

```
agentcore-foundation (Gateway, Identity, Observability)
         │
         ├─> agentcore-tools (Code Interpreter, Browser)
         │
         ├─> agentcore-runtime (Runtime, Memory, Packaging)
         │           │
         │           └─> agentcore-governance (Policy, Evaluations)
```

## Quick Start

### 1. Prerequisites

- Terraform >= 1.10.0 (required for native S3 state locking)
- AWS CLI configured with appropriate credentials
- AWS account with Bedrock AgentCore permissions
- Python 3.12+ (for packaging)

**Recommended**: Use `.terraform-version` file with tfenv/asdf for version management.

### 2. Clone and Initialize

```bash
cd terraform
terraform init
```

### 3. Configure Variables

Copy and customize the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
```

### 4. Deploy

```bash
terraform plan
terraform apply
```

## Feature Configuration

### Foundation Module (Terraform-Native)

Enable MCP gateway for tool integration, workload identity, and observability:

```hcl
enable_gateway              = true
gateway_search_type         = "HYBRID"

# RECOMMENDED: Use MCP servers module for automatic ARN resolution
# See examples/5-integrated/ for the full pattern
mcp_targets = module.mcp_servers.mcp_targets

# OR manual configuration with alias ARNs for versioning:
mcp_targets = {
  tool_name = {
    name        = "my-tool"
    lambda_arn  = "arn:aws:lambda:REGION:ACCOUNT:function:NAME:live"  # Use alias ARN
    version     = "1"  # Optional: Lambda version for audit trail
    description = "Tool description"
  }
}

enable_identity             = true
oauth_return_urls           = ["https://myapp.com/callback"]

enable_observability        = true
enable_xray                 = true
log_retention_days          = 30

# Note: AWS-managed encryption (SSE-S3) is used by default
# Customer-managed KMS is deprecated - see ADR-0008
```

**Status**: ✅ Fully Terraform-native
- `aws_bedrockagentcore_gateway`
- `aws_bedrockagentcore_gateway_target`
- `aws_bedrockagentcore_workload_identity`
- `aws_cloudwatch_log_group`
- `aws_xray_sampling_rule`

### Tools Module (Terraform-Native)

Enable Code Interpreter and Browser tools:

```hcl
enable_code_interpreter         = true
code_interpreter_network_mode   = "SANDBOX"  # PUBLIC, SANDBOX, VPC

enable_browser                  = true
browser_network_mode            = "SANDBOX"
enable_browser_recording        = true
browser_recording_s3_bucket     = "my-bucket"
```

**Status**: ✅ Fully Terraform-native
- `aws_bedrockagentcore_code_interpreter`
- `aws_bedrockagentcore_browser`

### Runtime Module (CLI-Based)

Configure agent execution and state:

```hcl
enable_runtime            = true
runtime_source_path       = "./agent-code"
runtime_entry_file        = "runtime.py"
runtime_config = {
  max_iterations = 10
  timeout_seconds = 300
}

enable_memory            = true
memory_type              = "BOTH"  # SHORT_TERM, LONG_TERM, BOTH

enable_packaging         = true
python_version           = "3.12"
```

**Status**: ⚠️ CLI-based (via `null_resource` + `local-exec`)
- Two-stage build process (OCDS-compliant)
- Automatic deployment to S3
- Hash-based change detection

**Process**:
1. Stage 1: Package dependencies from `pyproject.toml`
2. Stage 2: Create complete deployment package and upload to S3
3. Runtime creation via AWS CLI (`bedrock-agentcore-control create-agent-runtime`)

### Governance Module (CLI-Based)

Enable policy enforcement and quality evaluation:

```hcl
enable_policy_engine    = true
cedar_policy_files = {
  pii_protection = "./cedar_policies/pii-protection.cedar"
  rate_limiting  = "./cedar_policies/rate-limiting.cedar"
}

enable_evaluations      = true
evaluation_type         = "TOOL_CALL"  # TOOL_CALL, REASONING, RESPONSE, ALL
evaluator_model_id      = "anthropic.claude-sonnet-4-5"
evaluation_prompt       = "Evaluate response quality..."
evaluation_criteria = {
  accuracy = "Factual correctness"
  relevance = "Relevance to query"
}
```

**Status**: ⚠️ CLI-based (via `null_resource` + `local-exec`)
- Policy engine creation
- Cedar policy file management
- Evaluator setup
- CloudWatch monitoring

**Process**:
1. Create policy engine via AWS CLI
2. Deploy Cedar policies to engine
3. Create custom evaluator with specified model

## Example Configurations

### Example 1: Hello World (Minimal)

A simple S3 explorer agent demonstrating basic BedrockAgentCoreApp usage:

```bash
terraform apply -var-file="examples/1-hello-world/terraform.tfvars"
```

**Features**:
- Basic runtime configuration
- CloudWatch observability
- AWS-managed encryption

### Example 2: Gateway Tool (Titanic Analysis)

MCP gateway integration with Lambda tool for data analysis:

```bash
terraform apply -var-file="examples/2-gateway-tool/terraform.tfvars"
```

**Features**:
- MCP gateway with Lambda target
- Code interpreter for pandas analysis
- Demonstrates MCP protocol integration

### Example 3: Deep Research Agent (Full-Featured)

Production-ready research agent using Strands DeepAgents framework:

```bash
terraform apply -var-file="examples/3-deepresearch/terraform.tfvars"
```

**Features**:
- Strands DeepAgents multi-agent framework
- Internet search integration via Linkup SDK
- Code interpreter and web browser
- Short-term and long-term memory
- Session output storage to S3
- Langfuse telemetry integration

### Example 4: Research Agent (Simple)

Simplified research agent as a starting point:

```bash
terraform apply -var-file="examples/4-research/terraform.tfvars"
```

**Features**:
- MCP gateway with research tools
- Code interpreter for analysis
- Memory for context retention
- Quality evaluation

### Example 5: Integrated (Recommended Pattern)

Complete module composition with MCP servers and AgentCore:

```bash
cd examples/5-integrated
terraform init
terraform apply
```

**Features**:
- MCP servers deployed as submodule
- Automatic ARN resolution (no hardcoding)
- Lambda versioning with aliases for rollback
- Two-stage packaging (dependencies + code)
- Single `terraform apply` deploys everything

**Pattern**:
```hcl
# Deploy MCP servers first
module "mcp_servers" {
  source      = "../mcp-servers/terraform"
  environment = var.environment
}

# Then AgentCore with automatic ARN resolution
module "agentcore" {
  source      = "../../"
  mcp_targets = module.mcp_servers.mcp_targets  # No hardcoded ARNs!
  depends_on  = [module.mcp_servers]
}
```

### MCP Servers Module

Standalone Lambda-based MCP servers for tool integration:

```bash
cd examples/mcp-servers
make setup    # Install dependencies
make dev      # Start local server for testing
make validate # Validate Terraform
make deploy   # Deploy to AWS
```

**Available Servers**:
- `s3-tools` - S3 bucket and object operations
- `titanic-data` - Titanic dataset for analysis demos
- `local-dev` - Local Flask server for development

See `examples/mcp-servers/README.md` for full documentation.

## Deployment Patterns

### Pattern 1: Gateway Only (Minimal)

For agents that only need tool integration via MCP:

```hcl
enable_gateway              = true
enable_code_interpreter     = false
enable_browser              = false
enable_runtime              = false
enable_evaluations          = false
enable_policy_engine        = false
```

### Pattern 2: Agentic Runtime (Full Capabilities)

For autonomous agents with all features:

```hcl
enable_gateway              = true
enable_code_interpreter     = true
enable_browser              = true
enable_runtime              = true
enable_memory               = true
enable_evaluations          = true
enable_policy_engine        = true
```

### Pattern 3: Secure Production

For production deployments with security hardening:

```hcl
# AWS-managed encryption (SSE-S3) applied by default
enable_observability          = true
enable_xray                   = true
code_interpreter_network_mode = "VPC"  # With VPC endpoints
browser_network_mode          = "VPC"
enable_policy_engine          = true
enable_evaluations            = true
enable_browser_recording      = true
log_retention_days            = 90

# Use module composition for MCP targets (no hardcoded ARNs)
mcp_targets = module.mcp_servers.mcp_targets
```

## Networking Configuration

### Code Interpreter and Browser VPC Setup

For private execution within your VPC:

```hcl
code_interpreter_vpc_config = {
  subnet_ids         = ["subnet-xxxxx", "subnet-yyyyy"]
  security_group_ids = ["sg-xxxxx"]
  associate_public_ip = false
}

browser_vpc_config = {
  subnet_ids         = ["subnet-xxxxx", "subnet-yyyyy"]
  security_group_ids = ["sg-xxxxx"]
  associate_public_ip = false
}
```

## Security Features

### Encryption

By default, this project uses **AWS-managed encryption** (SSE-S3) for simplicity:

- **At Rest**: AWS-managed encryption for S3, default CloudWatch encryption
- **In Transit**: HTTPS/TLS for all API calls
- **No Key Management**: No customer KMS keys to manage or pay for

```hcl
# AWS-managed encryption is the default (no configuration needed)
# For customer-managed KMS (only if regulatory requirements mandate it):
# enable_kms = true
# kms_key_arn = "arn:aws:kms:..."
```

See `docs/adr/0008-aws-managed-encryption.md` for the rationale behind this decision.

### IAM Least Privilege

- Function-specific roles for each component
- Granular permissions per resource
- No wildcard permissions (except required by service)

```hcl
# Example: Code interpreter gets only necessary permissions
{
  "Effect": "Allow",
  "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
  "Resource": "arn:aws:logs:*:*:log-group:/aws/bedrock/agentcore/code-interpreter/*"
}
```

### Policy Engine & Evaluation

Enable Cedar policies for access control:

```hcl
enable_policy_engine = true
cedar_policy_files = {
  pii_protection = "./cedar_policies/pii-protection.cedar"
}
```

See `modules/agentcore-governance/cedar_policies/` for policy examples.

## State Management

### Terraform State

Recommended configuration for production (Terraform 1.10.0+):

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket       = "terraform-state-prod"
    key          = "bedrock-agentcore/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true  # Native S3 locking (no DynamoDB needed)
  }
}
```

**Note**: Native S3 locking via `use_lockfile = true` is the recommended approach. DynamoDB-based locking is deprecated.

### CLI Resource Outputs

CLI-provisioned resources store outputs in `.terraform/`:

```
.terraform/
├── runtime_output.json      # Runtime creation output
├── runtime_id.txt          # Runtime ID for reference
├── policy_engine.json      # Policy engine creation output
├── policy_engine_id.txt    # Policy engine ID
└── evaluator.json          # Evaluator creation output
```

These are read via `data "external"` sources and exposed as Terraform outputs.

## Outputs

After successful deployment:

```bash
terraform output
```

Key outputs include:
- `gateway_id`, `gateway_arn`, `gateway_endpoint`
- `code_interpreter_id`, `browser_id`
- `runtime_id`, `short_term_memory_id`, `long_term_memory_id`
- `policy_engine_id`, `evaluator_id`
- `deployment_bucket_name`
- `agent_summary` - overview of deployed features

## Monitoring and Logging

### CloudWatch Logs

View agent execution logs:

```bash
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

Available log groups:
- `/aws/bedrock/agentcore/runtime/<agent-name>` - Agent execution
- `/aws/bedrock/agentcore/gateway/<agent-name>` - Gateway activity
- `/aws/bedrock/agentcore/code-interpreter/<agent-name>` - Code execution
- `/aws/bedrock/agentcore/browser/<agent-name>` - Browser activity
- `/aws/bedrock/agentcore/policy-engine/<agent-name>` - Policy decisions
- `/aws/bedrock/agentcore/evaluator/<agent-name>` - Evaluation results

### X-Ray Tracing

Trace request flow through the agent:

```bash
aws xray get-service-graph --start-time <timestamp> --end-time <timestamp>
```

### CloudWatch Metrics and Alarms

Automatic alarms for:
- Gateway errors (threshold: 5+ in 5 minutes)
- Target invocation duration (threshold: 30+ seconds)
- Evaluation errors (threshold: 5+ in 5 minutes)
- Evaluation latency (threshold: 5+ seconds)

View alarms:

```bash
aws cloudwatch describe-alarms --alarm-names <agent-name>-gateway-errors
```

## Advanced Usage

### Multi-Environment Deployment

Deploy the same agent to dev, staging, and prod:

```bash
# Dev
terraform apply -var-file="environments/dev.tfvars"

# Staging
terraform apply -var-file="environments/staging.tfvars"

# Production
terraform apply -var-file="environments/prod.tfvars"
```

### Custom IAM Policies

Attach additional policies to runtime role:

```hcl
runtime_policy_arns = [
  "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  "arn:aws:iam::123456789012:policy/CustomAgentPolicy"
]
```

### Bring Your Own Infrastructure

Use existing resources instead of creating new ones:

```hcl
deployment_bucket_name  = "existing-bucket"
runtime_role_arn        = "arn:aws:iam::123456789012:role/existing-role"
policy_engine_role_arn  = "arn:aws:iam::123456789012:role/existing-policy-role"
evaluator_role_arn      = "arn:aws:iam::123456789012:role/existing-evaluator-role"
```

## Migration from Reference Implementation

If migrating from `deepagents-bedrock-agentcore-terraform`:

### Backward Compatibility

Existing configurations continue to work unchanged:

```hcl
# Old configuration still works
module "my_agent" {
  source = "./modules/agentcore"

  agent_name          = "my-agent"
  runtime_source_path = "../my-agent"
  enable_memory       = true
  # No other changes needed
}
```

### Opt-in Enhancements

Gradually enable new features:

```hcl
module "my_agent" {
  source = "./modules/agentcore"

  agent_name          = "my-agent"
  runtime_source_path = "../my-agent"
  enable_memory       = true

  # NEW: opt-in to Terraform-native features
  enable_gateway              = true
  enable_code_interpreter     = true
  enable_browser              = true
  enable_observability        = true
}
```

## Troubleshooting

### Runtime Creation Fails

If `bedrock-agentcore-control create-agent-runtime` is not available:

1. Verify AWS CLI is updated: `aws --version`
2. Check IAM permissions for the runtime role
3. Ensure deployment package exists in S3
4. Review logs: `aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow`

### Packaging Fails

If code packaging step fails:

1. Verify source path exists: `ls <runtime_source_path>`
2. Check pip can install dependencies: `pip install -r <source>/requirements.txt`
3. Review temp files in `terraform/.terraform/`
4. Run with verbose output: `terraform apply -var-file=<vars> -var="enable_packaging=true"`

### Policy Engine Creation Fails

If policy engine creation times out:

1. Verify Cedar policies are valid syntax
2. Check policy file paths are correct
3. Ensure policy engine role has required permissions
4. Review AWS CLI command in `policy.tf`

### Memory Creation Fails

If memory creation returns errors:

1. Verify short-term vs. long-term memory is appropriate
2. Check CloudWatch logs for details
3. Ensure agent runtime exists first (memory depends on runtime)

## Contributing

To extend the architecture:

1. **Add new Terraform-native resources**: Extend the appropriate module (foundation/tools)
2. **Add CLI-based resources**: Follow the `null_resource` + `local-exec` pattern
3. **Add Cedar policies**: Place in `modules/agentcore-governance/cedar_policies/`
4. **Add examples**: Create new `.tfvars` file in `examples/`

## Cost Estimation

Typical monthly costs (per agent):

| Feature | Cost |
|---------|------|
| Gateway | $0.00 (free tier) |
| Code Interpreter | $1.00-$10.00 (per execution) |
| Browser | $0.50-$5.00 (per session) |
| CloudWatch Logs | $0.50-$5.00 |
| X-Ray | $0.50-$2.00 |
| S3 Storage | $0.023 (per GB) |
| **Total** | **~$3-$30+** |

Varies based on usage, region, and feature enablement.

## References

- [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agents.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cedar Policy Language](https://www.cedarpolicy.com/)
- [AWS CLI Bedrock AgentCore Control](https://docs.aws.amazon.com/cli/latest/reference/bedrock-agentcore-control/)

## License

MIT - See LICENSE file for details

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review CloudWatch logs in `/aws/bedrock/agentcore/`
3. Examine Terraform apply output for detailed error messages
4. Consult AWS Bedrock AgentCore documentation

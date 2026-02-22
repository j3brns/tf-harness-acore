# Quick Reference Guide - AWS Bedrock AgentCore Terraform

## Project Structure

```
repo-root/
├── terraform/
│   ├── modules/
│   │   ├── agentcore-foundation/    ← Gateway, Identity, Observability
│   │   ├── agentcore-tools/         ← Code Interpreter, Browser
│   │   ├── agentcore-runtime/       ← Runtime, Memory, Packaging
│   │   └── agentcore-governance/    ← Policies, Evaluations
│   ├── main.tf                      ← Compose modules
│   ├── variables.tf                 ← All configuration options
│   └── outputs.tf                   ← What gets deployed
├── examples/                        ← Configuration examples
└── README.md                        ← Detailed documentation
```

## Quick Deploy

```bash
# 1. Initialize
cd terraform
terraform init

# 2. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Deploy
terraform plan
terraform apply
```

## Common Commands

```bash
# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# View all outputs
terraform output

# Destroy everything
terraform destroy

# View specific resource
terraform state show aws_bedrockagentcore_gateway.main[0]
```

## Configuration Quick Guide

### Enable/Disable Features

```hcl
# Foundation (Gateway, Identity, Observability)
enable_gateway         = true    # MCP tool integration
enable_identity        = false   # OAuth2 workload identity
enable_observability   = true    # CloudWatch + X-Ray

# Tools
enable_code_interpreter = true   # Python execution
enable_browser          = false  # Web browsing

# Runtime & State
enable_runtime         = true    # Agent execution
enable_memory          = true    # Agent memory (short/long-term)

# Governance
enable_policy_engine   = false   # Cedar policy control
enable_evaluations     = false   # Quality assessment
```

### Network Configuration

```hcl
# Code Interpreter Network Mode
code_interpreter_network_mode = "SANDBOX"  # PUBLIC, SANDBOX, or VPC

# If VPC mode:
code_interpreter_vpc_config = {
  subnet_ids         = ["subnet-xxxxx"]
  security_group_ids = ["sg-xxxxx"]
  associate_public_ip = false
}

# Browser Network Mode
browser_network_mode = "SANDBOX"  # PUBLIC, SANDBOX, or VPC
```

### MCP Tool Integration

```hcl
mcp_targets = {
  my_tool = {
    name       = "my-tool-display-name"
    lambda_arn = "arn:aws:lambda:eu-west-2:123456789012:function:my-tool-mcp"
  }
  another_tool = {
    name       = "another-tool"
    lambda_arn = "arn:aws:lambda:eu-west-2:123456789012:function:another-tool-mcp"
  }
}
```

### Runtime Configuration

```hcl
# Source code
runtime_source_path = "./agent-code"
runtime_entry_file  = "runtime.py"

# Runtime settings
runtime_config = {
  max_iterations  = 10
  timeout_seconds = 300
}

# Memory type
enable_memory = true
memory_type   = "BOTH"  # SHORT_TERM, LONG_TERM, or BOTH

# Build settings
enable_packaging = true
python_version   = "3.12"
```

### Governance Configuration

#### Multi-Tenant Cedar Policies
Always include tenant isolation in your policies to follow **Rule 14.3**.

```cedar
permit(
    principal,
    action == Action::"InvokeAgent",
    resource
)
when {
    principal.tenant_id == resource.tenant_id &&
    principal.app_id == "prod-research"
};
```

```hcl
# Policy Engine
enable_policy_engine  = true
cedar_policy_files = {
  pii_protection = "./policies/cedar/pii-protection.cedar"
  rate_limiting  = "./policies/cedar/rate-limiting.cedar"
}

# Evaluations
enable_evaluations = true
evaluation_type    = "TOOL_CALL"  # TOOL_CALL, REASONING, RESPONSE, ALL
evaluator_model_id = "anthropic.claude-sonnet-4-5"
```

## Example Deployments

### Minimal Agent (Gateway Only)

```bash
terraform apply \
  -var="enable_gateway=true" \
  -var="enable_code_interpreter=false" \
  -var="enable_browser=false" \
  -var="enable_runtime=false"
```

### Full-Featured Agent

```bash
terraform apply \
  -var="enable_gateway=true" \
  -var="enable_code_interpreter=true" \
  -var="enable_browser=true" \
  -var="enable_runtime=true" \
  -var="enable_memory=true" \
  -var="enable_evaluations=true" \
  -var="enable_policy_engine=true"
```

### Pre-built Examples

```bash
# Research Agent (web browsing + code)
terraform apply -var-file="../examples/research-agent.tfvars"

# Support Agent (CRM + policies)
terraform apply -var-file="../examples/support-agent.tfvars"
```

## Output Values

```bash
# View all outputs
terraform output

# View specific output
terraform output gateway_id
terraform output deployment_bucket_name
terraform output agent_summary

# Get as JSON
terraform output -json
```

## Key Outputs

| Output | Purpose |
|--------|---------|
| `gateway_id` | MCP gateway identifier |
| `gateway_endpoint` | Gateway URL |
| `code_interpreter_id` | Python sandbox identifier |
| `browser_id` | Browser tool identifier |
| `deployment_bucket_name` | S3 bucket for agent code |
| `runtime_id` | Agent runtime identifier |
| `policy_engine_id` | Cedar policy engine identifier |
| `evaluator_id` | Evaluator identifier |

## Monitoring

### View Logs

```bash
# Gateway logs
aws logs tail /aws/bedrock/agentcore/gateway/<agent-name> --follow

# Runtime logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow

# Code interpreter logs
aws logs tail /aws/bedrock/agentcore/code-interpreter/<agent-name> --follow

# Browser logs
aws logs tail /aws/bedrock/agentcore/browser/<agent-name> --follow

# Policy engine logs
aws logs tail /aws/bedrock/agentcore/policy-engine/<agent-name> --follow

# Evaluator logs
aws logs tail /aws/bedrock/agentcore/evaluator/<agent-name> --follow
```

### CloudWatch Alarms

```bash
# List alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix <agent-name>

# View specific alarm
aws cloudwatch describe-alarms \
  --alarm-names <agent-name>-gateway-errors
```

### X-Ray Tracing

```bash
# View service map
aws xray get-service-graph \
  --start-time <timestamp> \
  --end-time <timestamp>

# View traces
aws xray batch-get-traces \
  --trace-ids <trace-id>
```

## Troubleshooting

### Module Failed to Validate

```bash
# Check all modules
terraform validate

# Check specific module
cd terraform/modules/agentcore-foundation
terraform validate
```

### Runtime Creation Failed

```bash
# Check deployment bucket
aws s3 ls s3://<bucket-name>/deployments/

# Check logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow

# Check IAM role
aws iam get-role --role-name <agent-name>-runtime-role
```

### Policy Creation Failed

```bash
# Check Cedar syntax
# Review cedar_policies/*.cedar files

# Check policy engine was created
cat terraform/modules/agentcore-governance/.terraform/policy_engine_id.txt
```

### Memory Creation Failed

```bash
# Ensure runtime exists first
terraform output runtime_id

# Check CloudWatch logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

## State Management

### Backup State

```bash
# Create backup
cp terraform.tfstate terraform.tfstate.backup-$(date +%s)

# Or use Makefile
make state-backup
```

### View State

```bash
# List all resources
terraform state list

# Show specific resource
terraform state show aws_bedrockagentcore_gateway.main[0]
```

## Security Checklist

- [ ] Use AWS-managed encryption by default; enable KMS only if required
- [ ] Use VPC for network isolation
- [ ] Configure security groups appropriately
- [ ] Enable X-Ray tracing (`enable_xray = true`)
- [ ] Set up CloudWatch alarms
- [ ] Enable policy engine for access control
- [ ] Configure log retention appropriately
- [ ] Review IAM roles (least privilege)
- [ ] Backup Terraform state
- [ ] Store secrets securely (use AWS Secrets Manager)

## Development Workflow

```bash
# 1. Validate
terraform validate

# 2. Format
terraform fmt -recursive

# 3. Plan
terraform plan -out=tfplan

# 4. Review plan output

# 5. Apply
terraform apply tfplan

# 6. Monitor
terraform output
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

## Cost Optimization

- Use `SANDBOX` network mode (cheaper than VPC)
- Disable unused features (code_interpreter, browser)
- Set appropriate log retention (30 days default)
- Use `enable_memory = false` if not needed
- Consider spot instances for non-critical agents

## Useful Links

- [AWS Bedrock AgentCore Docs](https://docs.aws.amazon.com/bedrock/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cedar Policy Language](https://www.cedarpolicy.com/)
- [CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)

## Common Patterns

### Multi-Environment Setup

```bash
# Development
terraform apply -var-file="environments/dev.tfvars"

# Staging
terraform apply -var-file="environments/staging.tfvars"

# Production
terraform apply -var-file="environments/prod.tfvars"
```

### Separate State Files

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "bedrock/agentcore/<env>/terraform.tfstate"
    region = "eu-west-2"
  }
}
```

### Custom IAM Policies

```hcl
runtime_policy_arns = [
  "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
]

runtime_inline_policies = {
  custom_policy = file("${path.module}/policies/custom.json")
}
```

## Support & Documentation

- Full docs: `README.md`
- Implementation details: `docs/archive/IMPLEMENTATION_SUMMARY.md` (archived)
- Example configs: `examples/*.tfvars`
- Module code: `terraform/modules/*/`

---

**Last Updated**: 2026-02-13
**Version**: 1.1.0
**Status**: Production Ready ✅ (Multi-Tenant Hardened)

# Setup Guide - AWS Bedrock AgentCore Terraform

Complete step-by-step guide for setting up and deploying your first AgentCore agent.

## Prerequisites

### 1. AWS Account Setup

- [ ] AWS account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] Credentials with permissions for:
  - Bedrock AgentCore resources
  - S3, Lambda, IAM, CloudWatch, KMS, X-Ray
  - VPC resources (if using VPC mode)

Check credentials:
```bash
aws sts get-caller-identity
```

### 2. System Requirements

- [ ] Terraform >= 1.5.0
- [ ] Python >= 3.9 (for packaging)
- [ ] Bash shell (for provisioner scripts)
- [ ] pip (Python package manager)

Check versions:
```bash
terraform version
python --version
```

### 3. AWS CLI Tools

```bash
# Install AWS CLI v2 if not present
# https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

# Verify installation
aws --version

# Verify Bedrock AgentCore tools are available
aws bedrock-agentcore-control help 2>/dev/null || echo "Note: bedrock-agentcore-control may not be available yet"
```

## Step 1: Clone/Download the Repository

```bash
# Option A: Clone from git
git clone <repository-url> bedrock-agentcore-terraform
cd bedrock-agentcore-terraform/terraform

# Option B: If already have the files
cd terraform
```

## Step 2: Initialize Terraform

```bash
# Download required providers
terraform init

# Expected output: "Terraform has been successfully configured!"
```

## Step 3: Choose Your Configuration

### Option A: Use Example Configuration

```bash
# For research agent
cp ../examples/research-agent.tfvars terraform.tfvars

# For support agent
cp ../examples/support-agent.tfvars terraform.tfvars

# OR use template
cp terraform.tfvars.example terraform.tfvars
```

### Option B: Create Custom Configuration

Create `terraform.tfvars`:

```hcl
region      = "us-east-1"
environment = "dev"
agent_name  = "my-first-agent"

tags = {
  Owner = "your-name@example.com"
  Team  = "YourTeam"
}

# Basic setup
enable_gateway              = true
enable_code_interpreter     = true
enable_browser              = false
enable_runtime              = true
enable_memory               = true
enable_observability        = true
enable_kms                  = true

# Set your agent source code path
runtime_source_path         = "../my-agent-code"
```

## Step 4: Customize Variables

Edit `terraform.tfvars`:

```bash
# Edit with your editor
nano terraform.tfvars
# or
vim terraform.tfvars
# or
code terraform.tfvars  # if using VSCode
```

### Key Variables to Customize

```hcl
# Required: Unique agent name
agent_name = "my-research-agent"

# Required: Path to agent source code
runtime_source_path = "../research-agent"

# Optional: MCP tools (Lambda functions you provide)
mcp_targets = {
  web_search = {
    name       = "web-search-tool"
    lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:web-search-mcp"
  }
}

# Optional: Agent behavior
runtime_config = {
  max_iterations  = 10
  timeout_seconds = 300
}
```

## Step 5: Prepare Agent Source Code

Create your agent directory structure:

```bash
# Create agent directory
mkdir -p ../my-agent-code
cd ../my-agent-code

# Create basic agent files
cat > runtime.py << 'EOF'
import json
import logging

logger = logging.getLogger(__name__)

async def run_agent(input_data: dict) -> dict:
    """Main agent function"""
    logger.info(f"Processing: {input_data}")

    # Your agent logic here
    result = {
        "status": "success",
        "output": "Agent executed successfully"
    }

    return result
EOF

# Create dependencies file
cat > pyproject.toml << 'EOF'
[project]
name = "my-agent"
version = "0.1.0"
requires-python = ">=3.12"

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "black>=23.0",
]
EOF

# Create __init__.py
touch __init__.py
```

## Step 6: Create MCP Lambda Functions (Optional)

If using MCP targets, create Lambda functions:

```bash
# Example: Simple search tool
cat > ../web-search-mcp/index.py << 'EOF'
def lambda_handler(event, context):
    """MCP tool handler"""
    query = event.get("query", "")

    # Implement your tool logic
    results = {
        "query": query,
        "results": []
    }

    return {
        "statusCode": 200,
        "body": results
    }
EOF

# Deploy to Lambda (you'll get the ARN after)
```

## Step 7: Validate Configuration

```bash
# Check Terraform syntax
terraform validate

# Expected: "Success! The configuration is valid."

# Format files
terraform fmt -recursive

# Check security issues (optional, requires Checkov)
# checkov -d . --framework terraform
```

## Step 8: Plan Deployment

```bash
# Review what will be created
terraform plan -out=tfplan

# Expected: Shows all resources that will be created
# Review the output carefully!
```

## Step 9: Deploy Resources

```bash
# Apply the plan
terraform apply tfplan

# This will:
# 1. Create MCP gateway
# 2. Create code interpreter
# 3. Create S3 deployment bucket
# 4. Package agent code (two-stage build)
# 5. Create CloudWatch log groups
# 6. Create IAM roles and policies
# 7. Create KMS encryption key
# 8. Set up monitoring and alarms

# Expected runtime: 2-5 minutes
```

## Step 10: Verify Deployment

```bash
# View outputs
terraform output

# Check specific resources
terraform output agent_summary

# Verify gateway was created
aws bedrock-agentcore-control describe-gateway \
  --gateway-identifier <gateway-id>

# Check S3 bucket
aws s3 ls s3://<deployment-bucket>/deployments/

# View logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

## Step 11: Monitor Your Agent

### CloudWatch Logs

```bash
# Watch runtime logs in real-time
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow

# View error logs
aws logs filter-log-events \
  --log-group-name /aws/bedrock/agentcore/runtime/<agent-name> \
  --filter-pattern ERROR
```

### CloudWatch Metrics

```bash
# List alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix <agent-name>

# Get alarm details
aws cloudwatch describe-alarms \
  --alarm-names <agent-name>-gateway-errors
```

### X-Ray Tracing

```bash
# View traces
aws xray get-service-graph \
  --start-time $(date -d '5 minutes ago' +%s) \
  --end-time $(date +%s)
```

## Step 12: Test Your Agent

### Via AWS CLI

```bash
# Test gateway (if available)
aws bedrock-agentcore-control invoke-agent \
  --agent-identifier <agent-id> \
  --input-text "Test message"
```

### Via CloudWatch Logs

```bash
# Check for execution logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow
```

## Next Steps

### Add Features

```hcl
# Enable more features in terraform.tfvars
enable_browser = true
enable_memory = true
enable_policy_engine = true
enable_evaluations = true

# Reapply
terraform apply
```

### Create Cedar Policies

```bash
# Create policy file
cat > cedar_policies/access-control.cedar << 'EOF'
permit (
  principal,
  action == Action::"invoke",
  resource
)
when {
  principal.role == Role::"admin"
};
EOF

# Enable in terraform.tfvars
enable_policy_engine = true
cedar_policy_files = {
  access_control = "./cedar_policies/access-control.cedar"
}
```

### Scale to Production

```bash
# Create prod configuration
cp terraform.tfvars terraform.prod.tfvars

# Customize for production
# - enable_kms = true
# - log_retention_days = 90
# - code_interpreter_network_mode = "VPC"
# - Set up proper backend state

# Deploy
terraform apply -var-file="terraform.prod.tfvars"
```

## Troubleshooting

### "terraform: command not found"

```bash
# Install Terraform
# https://www.terraform.io/downloads

# Or use package manager
# Ubuntu/Debian
sudo apt-get install terraform

# macOS
brew install terraform

# Windows
choco install terraform
```

### "aws: command not found"

```bash
# Install AWS CLI
# https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

# Verify
aws --version
```

### "InvalidCredentialException"

```bash
# Ensure AWS credentials are configured
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_REGION=us-east-1

# Verify
aws sts get-caller-identity
```

### "Module not found"

```bash
# Ensure you're in terraform directory
cd terraform

# Reinitialize
terraform init
```

### "Error: S3 bucket does not exist"

This is normal during first deployment. The S3 bucket is created by Terraform. Check that `terraform apply` completed successfully.

### Runtime deployment hangs

```bash
# Check CloudWatch logs
aws logs tail /aws/bedrock/agentcore/packaging/<agent-name> --follow

# Check S3 bucket
aws s3 ls s3://<bucket-name>/deployments/

# You may need to update packaging scripts
```

## Cleanup

### Destroy All Resources

```bash
# WARNING: This deletes everything

# Review what will be destroyed
terraform plan -destroy

# Destroy
terraform destroy

# Or force destroy (use carefully)
terraform destroy -auto-approve
```

### Partial Cleanup

```bash
# Disable specific feature
enable_code_interpreter = false

# Apply to remove only that resource
terraform apply
```

## Getting Help

### 1. Check Logs

```bash
# Runtime logs
aws logs tail /aws/bedrock/agentcore/runtime/<agent-name> --follow

# Terraform logs
export TF_LOG=DEBUG
terraform apply
```

### 2. Review Terraform State

```bash
# List resources
terraform state list

# Check specific resource
terraform state show aws_bedrockagentcore_gateway.main[0]
```

### 3. Verify AWS Permissions

```bash
# Check current user
aws sts get-caller-identity

# List policies
aws iam list-attached-user-policies --user-name <your-username>
```

### 4. Consult Documentation

- **Full Documentation**: `README.md`
- **Quick Reference**: `QUICK_REFERENCE.md`
- **Implementation Details**: `docs/archive/IMPLEMENTATION_SUMMARY.md` (archived)

## Success Checklist

- [ ] Terraform validates without errors
- [ ] terraform plan shows resources to create
- [ ] terraform apply completes successfully
- [ ] Gateway is created and functional
- [ ] Agent code packaged in S3
- [ ] CloudWatch logs show activity
- [ ] All alarms are healthy
- [ ] Can view outputs: `terraform output`

Once all items are checked, your agent is ready! 🚀

---

**Next**: Read `README.md` for advanced configuration options.

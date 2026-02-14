# Runbook: Deployment Rollback

## Overview

Procedures for rolling back AgentCore deployments.

## Rollback Types

### 1. Lambda MCP Server Rollback (Fast - No Terraform)

**When to use:** MCP server code issue, Gateway still working

**Steps:**

```bash
# 1. List Lambda versions
aws lambda list-versions-by-function \
  --function-name agentcore-mcp-s3-tools-${ENV}

# 2. Update alias to previous version
aws lambda update-alias \
  --function-name agentcore-mcp-s3-tools-${ENV} \
  --name live \
  --function-version <PREVIOUS_VERSION>

# 3. Verify
aws lambda get-alias \
  --function-name agentcore-mcp-s3-tools-${ENV} \
  --name live
```

**Recovery time:** < 1 minute

### 2. Terraform Rollback (Medium)

**When to use:** Infrastructure configuration issue

**Steps:**

```bash
# 1. Identify the previous good state
git log --oneline terraform/

# 2. Checkout previous version
git checkout <COMMIT_HASH> -- terraform/

# 3. Review changes
terraform plan

# 4. Apply rollback
terraform apply
```

**Recovery time:** 5-15 minutes

### 3. Full Environment Rollback (Slow)

**When to use:** Major issue affecting multiple components

**Steps:**

```bash
# 1. Stop all deployments
# (Cancel running pipelines in GitLab)

# 2. Identify last known good tag
git tag -l 'v*' --sort=-creatordate | head -5

# 3. Checkout and deploy
git checkout <TAG>
cd terraform
terraform init
terraform apply

# 4. Verify all components
aws bedrock-agentcore-control list-gateways
aws bedrock-agentcore-control list-runtimes
```

**Recovery time:** 15-30 minutes

## Rollback Decision Matrix

| Issue | Rollback Type | Est. Time |
|-------|---------------|-----------|
| MCP tool bug | Lambda alias | < 1 min |
| Gateway config | Terraform | 5-10 min |
| IAM permission | Terraform | 5-10 min |
| Tenant Isolation Error | Hot-fix / Patch | 5-10 min |
| Multiple components | Full env | 15-30 min |
| State corruption | State recovery | 10-20 min |

## Post-Rollback

1. **Notify team** of rollback
2. **Create incident ticket**
3. **Root cause analysis** within 24 hours
4. **Fix forward** in new deployment
5. **Update runbooks** if needed

## Prevention

- Always test in dev before prod
- Use Lambda versioning with aliases
- Tag releases before deployment
- Keep rollback scripts tested monthly

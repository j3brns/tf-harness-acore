# Runbook: Common Failure Scenarios

## Overview

Quick reference for common failures and their resolutions.

---

## 1. Lambda Invocation Failures

### Error: "Task timed out"

**Cause:** Lambda execution exceeded timeout

**Resolution:**
```bash
# 1. Check current timeout
aws lambda get-function-configuration \
  --function-name agentcore-mcp-s3-tools-${ENV} \
  --query 'Timeout'

# 2. Increase timeout (max 900 seconds)
aws lambda update-function-configuration \
  --function-name agentcore-mcp-s3-tools-${ENV} \
  --timeout 60

# 3. Or update in Terraform
# terraform/examples/mcp-servers/terraform/main.tf
# variable "lambda_timeout" default = 60
```

### Error: "AccessDeniedException"

**Cause:** Lambda IAM role missing permissions

**Resolution:**
```bash
# 1. Check Lambda role
aws lambda get-function-configuration \
  --function-name agentcore-mcp-s3-tools-${ENV} \
  --query 'Role'

# 2. Check role policies
aws iam list-role-policies --role-name <ROLE_NAME>
aws iam list-attached-role-policies --role-name <ROLE_NAME>

# 3. Add missing policy via Terraform
# Update modules/agentcore-foundation/iam.tf
```

---

## 2. Gateway Failures

### Error: "Gateway not responding"

**Resolution:**
```bash
# 1. Check gateway status
aws bedrock-agentcore-control describe-gateway \
  --gateway-id <GATEWAY_ID>

# 2. Check CloudWatch logs
aws logs tail /aws/bedrock/agentcore/gateway/${AGENT_NAME} --follow

# 3. Verify Lambda targets are reachable
aws lambda invoke \
  --function-name agentcore-mcp-s3-tools-${ENV} \
  --payload '{"tool": "list_buckets"}' \
  response.json
```

### Error: "Invalid MCP target ARN"

**Cause:** Lambda ARN doesn't exist or wrong format

**Resolution:**
```bash
# 1. Verify Lambda exists
aws lambda get-function \
  --function-name <FUNCTION_NAME>

# 2. Check ARN format (should include alias for versioning)
# Correct: arn:aws:lambda:REGION:ACCOUNT:function:NAME:live
# Wrong:   arn:aws:lambda:REGION:ACCOUNT:function:NAME

# 3. Use module outputs instead of hardcoded ARNs
# mcp_targets = module.mcp_servers.mcp_targets
```

---

## 3. S3 Packaging Failures

### Error: "NoSuchBucket"

**Cause:** Deployment bucket doesn't exist

**Resolution:**
```bash
# 1. Check if bucket exists
aws s3 ls | grep agentcore-deployment

# 2. If not, run Terraform
terraform apply -target=module.agentcore_runtime.aws_s3_bucket.deployment

# 3. Verify bucket
aws s3 ls s3://agentcore-deployment-${ENV}-${ACCOUNT_ID}/
```

### Error: "Empty zip created"

**Cause:** Source path doesn't exist or is empty

**Resolution:**
```bash
# 1. Verify source path
ls -la ./agent-code/

# 2. Check Terraform variable
terraform console
> var.runtime_source_path

# 3. Ensure files exist
find ./agent-code -name "*.py" | head -5
```

---

## 4. Terraform Failures

### Error: "Provider configuration not present"

**Resolution:**
```bash
terraform init -reconfigure
```

### Error: "Resource already exists"

**Resolution:**
```bash
# Import existing resource
terraform import <RESOURCE_TYPE>.<NAME> <RESOURCE_ID>
```

### Error: "Placeholder ARN detected"

**Cause:** Using example ARN with 123456789012

**Resolution:**
```bash
# 1. Use module outputs
mcp_targets = module.mcp_servers.mcp_targets

# 2. Or get real ARN
aws lambda get-function --function-name <NAME> --query 'Configuration.FunctionArn'
```

---

## 5. CI/CD Pipeline Failures

### Error: "WIF token expired"

**Cause:** Long-running job exceeded token lifetime

**Resolution:**
- Split job into smaller stages
- Increase token lifetime in GitLab settings

### Error: "terraform init failed in CI"

**Resolution:**
```bash
# 1. Check backend config
cat backend-${ENV}.tf

# 2. Verify S3 bucket exists
aws s3 ls terraform-state-${ENV}-${PROJECT_ID}

# 3. Verify DynamoDB table exists
aws dynamodb describe-table --table-name terraform-state-lock-${ENV}
```

---

## Quick Reference

| Error | First Check | Quick Fix |
|-------|-------------|-----------|
| Timeout | CloudWatch logs | Increase timeout |
| Access denied | IAM policies | Add missing permission |
| Gateway down | Lambda targets | Test Lambda directly |
| Empty zip | Source path | Verify files exist |
| Provider missing | terraform init | Run init -reconfigure |
| Placeholder ARN | Variable value | Use module outputs |

## Escalation Path

1. **P1 (Production down):** Page on-call → DevOps lead → Engineering manager
2. **P2 (Degraded):** Slack #agentcore-alerts → DevOps
3. **P3 (Non-critical):** Create ticket → Next sprint

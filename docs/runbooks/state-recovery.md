# Runbook: Terraform State Recovery

## Overview

This runbook covers recovery procedures for Terraform state issues.

## Scenarios

### 1. State File Corruption

**Symptoms:**
- `terraform plan` fails with parse errors
- Error: "Error loading state: ..."

**Recovery Steps:**

```bash
# 1. List available state versions (S3 versioning)
aws s3api list-object-versions \
  --bucket terraform-state-${ENV}-${PROJECT_ID} \
  --prefix agentcore/terraform.tfstate

# 2. Download a known-good version
aws s3api get-object \
  --bucket terraform-state-${ENV}-${PROJECT_ID} \
  --key agentcore/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.recovered

# 3. Verify the recovered state
terraform show terraform.tfstate.recovered

# 4. Replace current state
aws s3 cp terraform.tfstate.recovered \
  s3://terraform-state-${ENV}-${PROJECT_ID}/agentcore/terraform.tfstate

# 5. Verify recovery
terraform init
terraform plan
```

### 2. State Lock Stuck

**Symptoms:**
- Error: "Error acquiring the state lock"
- Previous apply interrupted

**Recovery Steps:**

```bash
# 1. Check lock status
aws dynamodb get-item \
  --table-name terraform-state-lock-${ENV} \
  --key '{"LockID": {"S": "terraform-state-${ENV}/agentcore/terraform.tfstate"}}'

# 2. Force unlock (DANGEROUS - ensure no other operations running)
terraform force-unlock <LOCK_ID>

# 3. If DynamoDB issue, manually delete lock
aws dynamodb delete-item \
  --table-name terraform-state-lock-${ENV} \
  --key '{"LockID": {"S": "terraform-state-${ENV}/agentcore/terraform.tfstate"}}'
```

### 3. State Drift Detection

**Symptoms:**
- Resources modified outside Terraform
- `terraform plan` shows unexpected changes

**Recovery Steps:**

```bash
# 1. Run detailed plan
terraform plan -detailed-exitcode

# 2. For each drifted resource, decide:
#    a) Accept current state (refresh)
#    b) Revert to Terraform config (apply)

# 3. If accepting current state:
terraform refresh

# 4. If reverting:
terraform apply -target=<RESOURCE>
```

## Prevention

1. **Enable S3 versioning** on state bucket
2. **Use DynamoDB locking** to prevent concurrent modifications  
3. **Never modify state manually** - use `terraform state` commands
4. **Run weekly drift detection** in CI/CD pipeline
5. **Test state recovery monthly** in dev environment

## Escalation

If recovery fails:
1. Contact DevOps lead
2. Restore from backup state
3. Document incident in post-mortem

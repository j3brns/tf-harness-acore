# Runbook: Terraform State Recovery

## Overview

This runbook covers recovery procedures for Terraform state issues.

## Scenarios

Set the state key variables for the environment you are recovering. The repo-standard CI backend key is segmented by environment + app + agent (`agentcore/${ENV}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate`).

```bash
export ENV="<dev|test|prod>"
export PROJECT_ID="<project-or-account-suffix>"
export TF_STATE_APP_ID="<app-id-slug>"
export TF_STATE_AGENT_NAME="<agent-name-slug>"
export STATE_BUCKET="terraform-state-${ENV}-${PROJECT_ID}"
export STATE_KEY="agentcore/${ENV}/${TF_STATE_APP_ID}/${TF_STATE_AGENT_NAME}/terraform.tfstate"
# Legacy (pre-ADR-0013 migration) fallback:
# export STATE_KEY="agentcore/${ENV}/terraform.tfstate"
```

### 1. State File Corruption

**Symptoms:**
- `terraform plan` fails with parse errors
- Error: "Error loading state: ..."

**Recovery Steps:**

```bash
# 1. List available state versions (S3 versioning)
aws s3api list-object-versions \
  --bucket "${STATE_BUCKET}" \
  --prefix "${STATE_KEY}"

# 2. Download a known-good version
aws s3api get-object \
  --bucket "${STATE_BUCKET}" \
  --key "${STATE_KEY}" \
  --version-id <VERSION_ID> \
  terraform.tfstate.recovered

# 3. Verify the recovered state
terraform show terraform.tfstate.recovered

# 4. Replace current state
aws s3 cp terraform.tfstate.recovered \
  "s3://${STATE_BUCKET}/${STATE_KEY}"

# 5. Verify recovery
terraform init
terraform plan
```

### 2. State Lock Stuck (Native S3)

**Symptoms:**
- Error: "Error acquiring the state lock"
- Previous apply interrupted

**Recovery Steps:**

Terraform 1.10+ uses **Native S3 locking**. A lock file is created at `${STATE_KEY}.tflock` (for example `agentcore/dev/app/agent/terraform.tfstate.tflock`).

```bash
# 1. Identify the lock ID from the error message
# Example: "ID: 12345678-abcd-..."

# 2. Force unlock (DANGEROUS - ensure no other operations running)
terraform force-unlock <LOCK_ID>

# 3. If S3 object remains, manually delete the .tflock file
aws s3 rm "s3://${STATE_BUCKET}/${STATE_KEY}.tflock"
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

1. **Enable S3 versioning** on state bucket.
2. **Use native S3 locking** (`use_lockfile = true`) to prevent concurrent modifications.
3. **Never modify state manually** - use `terraform state` commands.
4. **Run weekly drift detection** in CI/CD pipeline.
5. **Test state recovery monthly** in dev environment.

## Escalation

If recovery fails:
1. Contact DevOps lead
2. Restore from backup state
3. Document incident in post-mortem

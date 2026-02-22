# Runbook: Segmented Terraform State Key Migration

## Purpose
This runbook defines the procedure for migrating an existing Bedrock AgentCore Terraform state from the legacy, hardcoded state key to the new segmented structure as defined in [ADR 0013](../adr/0013-segmented-state-key-strategy.md).

**Legacy Key Pattern**: `agentcore/terraform.tfstate`
**New Key Pattern**: `state/${app_id}/${agent_name}/terraform.tfstate`

## Preconditions
1. **Terraform Version**: >= 1.10.0 (required for native S3 locking).
2. **State Backup**: Access to the current S3 state bucket with versioning enabled.
3. **Permissions**: IAM permissions to read/write/delete objects in the state bucket.
4. **Locking**: No concurrent operations are running against the current state.

## Pre-Flight Checklist
Run from the `terraform/` directory.

1. **Backup State**: Capture a local backup of the current state.
   ```bash
   terraform state pull > pre-migration-$(date +%Y%m%d).tfstate
   ```

2. **Verify Baseline**: Ensure the current state is clean and matches the remote.
   ```bash
   terraform plan -refresh-only
   ```
   *Gate: Stop if there is unexpected drift.*

## Execution Procedure

### Step 1: Prepare Backend Configuration
Create a temporary backend configuration file (e.g., `migrate.tfvars`) containing the NEW key.

```hcl
# migrate.tfvars
bucket       = "terraform-state-<env>-<id>"
key          = "state/<app_id>/<agent_name>/terraform.tfstate"
region       = "eu-central-1"
encrypt      = true
use_lockfile = true
```

Replace `<env>`, `<id>`, `<app_id>`, and `<agent_name>` with your actual values.

### Step 2: Initialize Migration
Run `terraform init` with the new backend configuration. Terraform will detect the change and prompt to migrate the state.

```bash
terraform init -backend-config=migrate.tfvars
```

When prompted:
> Do you want to copy existing state to the new backend?
> Enter a value: **yes**

### Step 3: Verify State Transition
Confirm that the state has been successfully moved to the new key.

1. **Check Local State**:
   ```bash
   terraform state list
   ```

2. **Check S3 Object**:
   Verify the new key exists in the S3 bucket:
   ```bash
   aws s3 ls s3://terraform-state-<env>-<id>/state/<app_id>/<agent_name>/terraform.tfstate
   ```

3. **Check Lock**:
   Verify native locking works by running a plan:
   ```bash
   terraform plan
   ```

### Step 4: Finalize Configuration
Update your project's permanent backend configuration (e.g., `backend-dev.tf`) to use the segmented pattern.

**Legacy**:
```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state-dev-12345"
    key    = "agentcore/terraform.tfstate"
  }
}
```

**New (Partial Backend)**:
```hcl
terraform {
  backend "s3" {
    # Key and bucket are provided via -backend-config during init
    # or via environment-specific .tfvars files.
    use_lockfile = true
    encrypt      = true
  }
}
```

## Rollback Procedure
If the migration fails or the state is corrupted:

1. **Restore from Backup**:
   Initialize with the OLD backend configuration and push the pre-migration state backup.
   ```bash
   # Revert backend config to legacy values
   terraform init -reconfigure
   
   # Push the backup (requires confirmation)
   terraform state push pre-migration-<date>.tfstate
   ```

2. **Verify**:
   Run `terraform plan` to confirm the baseline state is restored.

## Cleanup (Optional)
Once the migration is fully verified and applied in all environments, you may remove the legacy state object to avoid confusion.

**CAUTION**: Ensure you are deleting the OLD key, not the new one.
```bash
aws s3 rm s3://terraform-state-<env>-<id>/agentcore/terraform.tfstate
aws s3 rm s3://terraform-state-<env>-<id>/agentcore/terraform.tfstate.tflock
```

## References
- [ADR 0013: Segmented State Key Strategy](../adr/0013-segmented-state-key-strategy.md)
- [ADR 0004: State Management](../adr/0004-state-management.md)

# ADR 0004: S3 Backend with Native State Locking

## Status

Accepted (Updated)

## Context

Need remote state storage for:
- Team collaboration (multiple developers)
- State locking to prevent concurrent modifications
- State backup and recovery
- Three AWS accounts (dev, test, prod) with separate state

## Decision

Use S3 backend with **native S3 state locking** (Terraform 1.10.0+):
- Separate bucket per environment (`terraform-state-{env}-{id}`)
- Native S3 locking via `use_lockfile = true` (no DynamoDB required)
- Bucket versioning enabled (state backup/rollback)
- Encryption at rest (AES256 SSE-S3)

### Important: DynamoDB Locking is Deprecated

As of Terraform 1.10.0, S3 backends support native state locking. DynamoDB-based
locking is **deprecated** and will be removed in future Terraform versions.

Reference: [AWS Prescriptive Guidance - Backend Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html)

## Configuration Pattern

```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-state-dev-12345"
    key          = "agentcore/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true  # Native S3 locking (Terraform 1.10.0+)
  }
}
```

> **Note**: CI generates the backend key as `agentcore/${CI_ENVIRONMENT_NAME}/terraform.tfstate`.
> ADR 0013 documents a planned further segmentation (`agentcore/{env}/{app_id}/{agent_name}/terraform.tfstate`)
> and the migration runbook is in `docs/runbooks/segmented-terraform-state-key-migration.md`.

## State Structure

```
s3://terraform-state-dev-12345/
├── agentcore/
│   └── dev/
│       ├── terraform.tfstate        (current state)
│       ├── terraform.tfstate.tflock (lock file - created during operations)
│       └── [versioned snapshots]    (via S3 versioning)
```

## Rationale

- S3 provides reliable, durable state storage (11 9's durability)
- **Native S3 locking** eliminates DynamoDB dependency and cost
- Versioning enables rollback if state becomes corrupted
- Separate buckets provide blast radius containment
- Encryption protects sensitive state data
- Simpler infrastructure (no DynamoDB table to manage)

## Consequences

### Positive
- Team can collaborate safely
- State history maintained via S3 versioning
- Disaster recovery possible via version restore
- **Lower cost** (no DynamoDB charges)
- **Simpler setup** (only S3 bucket needed)
- Industry standard pattern
- Future-proof (DynamoDB locking deprecated)

### Negative
- Requires Terraform 1.10.0 or later
- Must create buckets before `terraform init`
- Requires S3 permissions for users
- State contains sensitive data (must encrypt)
- Cross-region access requires bucket replication

## Alternatives Considered

1. **DynamoDB Locking** - Rejected (deprecated, adds complexity and cost)
2. **Terraform Cloud** - Rejected (requires external SaaS)
3. **Local state** - Rejected (no collaboration, no backup)
4. **Single bucket for all environments** - Rejected (blast radius too large)
5. **Consul backend** - Rejected (additional infrastructure to manage)

## Prerequisites

Before first `terraform init`:

```bash
# Create S3 bucket with versioning and encryption
aws s3 mb s3://terraform-state-dev-12345 --region us-east-1

aws s3api put-bucket-versioning \
  --bucket terraform-state-dev-12345 \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket terraform-state-dev-12345 \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access
aws s3api put-public-access-block \
  --bucket terraform-state-dev-12345 \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

**Note**: No DynamoDB table creation needed with native S3 locking.

## Migration from DynamoDB Locking

If migrating from DynamoDB-based locking:

```hcl
# Step 1: Update backend config
terraform {
  backend "s3" {
    bucket       = "terraform-state-dev-12345"
    key          = "agentcore/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true  # Add this
    # dynamodb_table = "terraform-state-lock-dev"  # Remove this
  }
}

# Step 2: Reinitialize
terraform init -reconfigure
```

After successful migration, you can delete the DynamoDB table:
```bash
aws dynamodb delete-table --table-name terraform-state-lock-dev
```

## State Recovery

### Corrupted State
```bash
# List versions (replace key with your actual backend key)
aws s3api list-object-versions \
  --bucket terraform-state-dev-12345 \
  --prefix agentcore/dev/terraform.tfstate

# Restore specific version
aws s3api copy-object \
  --bucket terraform-state-dev-12345 \
  --copy-source "terraform-state-dev-12345/agentcore/dev/terraform.tfstate?versionId=VERSION_ID" \
  --key agentcore/dev/terraform.tfstate
```

### Stuck Lock
```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID

# Or manually delete lock file
aws s3 rm s3://terraform-state-dev-12345/agentcore/terraform.tfstate.tflock
```

## Version Requirements

- **Terraform**: >= 1.10.0 (for native S3 locking), recommended 1.14.x
- **AWS Provider**: >= 5.80.0 (recommended)

## References

- [AWS Prescriptive Guidance - Backend Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)

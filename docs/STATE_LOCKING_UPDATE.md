# State Locking Update: DynamoDB Deprecated

**Date**: 2026-02-08
**Status**: ✅ **NATIVE S3 LOCKING** (Terraform 1.10+)

---

## Summary

**DynamoDB tables are NO LONGER REQUIRED** for Terraform state locking.

Terraform 1.10+ introduced **native S3 state locking** using the `use_lockfile` parameter, eliminating the need for DynamoDB tables.

---

## What Changed

### ❌ **OLD (Pre-Terraform 1.10)**
```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-dev"
    key            = "agentcore/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-dev"  # ← DynamoDB required
  }
}
```

**Required AWS Resources**:
- S3 bucket
- DynamoDB table (for locking)

---

### ✅ **NEW (Terraform 1.10+)**
```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-state-dev"
    key          = "agentcore/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true  # ← Native S3 locking
  }
}
```

**Required AWS Resources**:
- S3 bucket (only!)

---

## Benefits

1. **Simpler**: No DynamoDB table to create/manage
2. **Cheaper**: No DynamoDB costs (~$0.30/month savings per environment)
3. **Fewer Permissions**: No DynamoDB IAM permissions needed
4. **Same Reliability**: S3 native locking is equally robust

---

## Migration Path

If you have existing DynamoDB tables:

1. **Update backend config**:
   ```hcl
   # Remove:
   # dynamodb_table = "terraform-state-lock-dev"

   # Add:
   use_lockfile = true
   ```

2. **Re-initialize Terraform**:
   ```bash
   terraform init -reconfigure
   ```

3. **Verify locking works**:
   ```bash
   # In terminal 1:
   terraform plan -out=test.tfplan &

   # In terminal 2 (should block):
   terraform plan
   # Should show: "Acquiring state lock..."
   ```

4. **Delete DynamoDB tables** (optional):
   ```bash
   aws dynamodb delete-table --table-name terraform-state-lock-dev
   aws dynamodb delete-table --table-name terraform-state-lock-test
   aws dynamodb delete-table --table-name terraform-state-lock-prod
   ```

---

## IAM Permission Changes

### ❌ **OLD (With DynamoDB)**
```json
{
  "Sid": "DynamoDBLocking",
  "Effect": "Allow",
  "Action": ["dynamodb:*"],
  "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock-*"
}
```

### ✅ **NEW (Native S3 Locking)**
**No DynamoDB permissions needed!** Just S3:

```json
{
  "Sid": "S3StateAndLocking",
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::terraform-state-*",
    "arn:aws:s3:::terraform-state-*/*"
  ]
}
```

---

## Compatibility

- **Terraform >= 1.10.0**: Native S3 locking available
- **Terraform < 1.10.0**: Must use DynamoDB

**This project requires Terraform >= 1.10.0** per `.terraform-version` file.

---

## Documentation to Update

Files that reference DynamoDB locking (all in `docs/archive/`):
- [x] ~~`docs/archive/IMPLEMENTATION_PLAN.md`~~ (archived, historical reference only)
- [ ] Check README.md for any DynamoDB references
- [ ] Check SETUP.md for backend configuration examples
- [ ] Update ADR 0004 (state-management.md) to reflect native locking

---

## Current Status

✅ **Project already uses S3 backend** - Just need to verify:
1. Backend configs use `use_lockfile = true` (not `dynamodb_table`)
2. IAM policies don't require DynamoDB permissions
3. Documentation references are updated

---

## References

- [Terraform 1.10 Release Notes](https://github.com/hashicorp/terraform/releases/tag/v1.10.0)
- [S3 Backend Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- ADR 0004: State Management

---

**Conclusion**: DynamoDB is deprecated for Terraform state locking. Use native S3 locking instead.

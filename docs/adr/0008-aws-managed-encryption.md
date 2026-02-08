# ADR 0008: Use AWS-Managed Encryption Instead of Customer-Managed KMS

## Status

Accepted

## Context

The original implementation included customer-managed KMS keys for encrypting:
- S3 deployment buckets
- CloudWatch log groups
- Bedrock AgentCore gateway configurations

Customer-managed KMS provides additional control over encryption keys but introduces:
- **Operational complexity**: Key rotation, policy management, deletion windows
- **Cost overhead**: $1/month per key + $0.03 per 10,000 API calls
- **Security risk**: Misconfigured KMS policies (SEC-007 identified `kms:*` wildcard)
- **Failure modes**: Deleted keys cause data loss, orphaned resources

## Decision

Remove customer-managed KMS in favor of AWS-managed encryption:

1. **S3 buckets**: Use SSE-S3 (AES256) instead of SSE-KMS
2. **CloudWatch logs**: Use default AWS-managed encryption
3. **Bedrock AgentCore**: Use service-managed encryption

## Rationale

### Security Equivalence
AWS-managed encryption provides:
- AES-256 encryption at rest (same algorithm as KMS)
- Automatic key rotation managed by AWS
- Keys that cannot be accidentally deleted or misconfigured
- No policy management required

### Operational Simplicity
- No KMS key provisioning or lifecycle management
- No IAM policy debugging for KMS access
- Simpler Terraform code (fewer resources)
- Faster deployment times

### Cost Reduction
- Eliminates ~$1-5/month in KMS charges per environment
- Reduces API call costs for decrypt/encrypt operations

### When Customer-Managed KMS Is Still Needed
Customer-managed KMS should be used when:
- Regulatory requirements mandate customer-controlled keys (HIPAA, PCI-DSS)
- Cross-account encryption key sharing is required
- Custom key rotation schedules are needed
- Audit requirements demand key usage logging

## Consequences

### Positive
- Simpler infrastructure code
- Reduced operational overhead
- Lower costs
- Eliminated SEC-007 vulnerability (no KMS policy to misconfigure)
- Faster `terraform apply` (no KMS resources to create)

### Negative
- Cannot use cross-account encryption
- Cannot customize key rotation schedule
- No key usage logging in CloudTrail (use S3/CloudWatch access logs instead)

### Migration Path
If customer-managed KMS is later required:
1. Create new KMS key with proper scoped policy
2. Update S3 bucket encryption configuration
3. Re-encrypt existing objects with `aws s3 cp --sse aws:kms`
4. Update Terraform to reference KMS key ARN

## Implementation

### Removed Resources
- `aws_kms_key.agentcore`
- `aws_kms_alias.agentcore`

### Updated Resources
```hcl
# S3 bucket encryption - BEFORE
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.agentcore[0].arn
    }
  }
}

# S3 bucket encryption - AFTER
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # AWS-managed SSE-S3
    }
  }
}
```

### Deprecated Variables
The following variables are now deprecated but retained for backward compatibility:
- `enable_kms` (defaults to `false`)
- `kms_key_arn` (unused)
- `kms_key_deletion_window` (unused)

## References

- [AWS S3 Encryption Options](https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html)
- [CloudWatch Logs Encryption](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html)
- SEC-007: KMS key policy uses wildcard permissions (senior engineer review)

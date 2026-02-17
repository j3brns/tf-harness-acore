# S3 bucket for deployment artifacts
resource "aws_s3_bucket" "deployment" {
  count         = var.deployment_bucket_name == "" ? 1 : 0
  bucket        = "${var.app_id}-${var.agent_name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = var.tags

  lifecycle {
    ignore_changes = [bucket]
  }
}

# S3 Access Logging
resource "aws_s3_bucket_logging" "deployment" {
  count  = var.deployment_bucket_name == "" && var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  target_bucket = var.logging_bucket_id
  target_prefix = "s3-access-logs/deployment/"
}

# Block public access to deployment bucket
resource "aws_s3_bucket_public_access_block" "deployment" {
  count  = var.deployment_bucket_name == "" ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 versioning
resource "aws_s3_bucket_versioning" "deployment" {
  count  = var.deployment_bucket_name == "" && var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 server-side encryption - Using AWS-managed encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  count  = var.deployment_bucket_name == "" && var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # AWS-managed encryption (SSE-S3)
    }
    bucket_key_enabled = true
  }
}

# S3 Lifecycle Rule - Expire old artifacts after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "deployment" {
  count  = var.deployment_bucket_name == "" ? 1 : 0
  bucket = aws_s3_bucket.deployment[0].id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CloudWatch log group for packaging
resource "aws_cloudwatch_log_group" "packaging" {
  count = var.enable_packaging ? 1 : 0

  name              = "/aws/bedrock/agentcore/packaging/${var.agent_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# CloudWatch log group for runtime
resource "aws_cloudwatch_log_group" "runtime" {
  count = var.enable_runtime ? 1 : 0

  name              = "/aws/bedrock/agentcore/runtime/${var.agent_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

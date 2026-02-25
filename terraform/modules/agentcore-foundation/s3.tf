# Centralized S3 Logging Bucket
resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_18: This is the logging bucket itself
  # checkov:skip=CKV_AWS_144: Single region design
  # checkov:skip=CKV_AWS_145: Using AWS-managed SSE-S3
  # checkov:skip=CKV_AWS_21: Versioning not required for access logs
  count  = var.enable_observability ? 1 : 0
  bucket = "${var.agent_name}-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = var.tags
}

# CloudFront standard logging (legacy S3 delivery via distribution logging_config)
# requires ACLs to be enabled on the destination bucket.
resource "aws_s3_bucket_ownership_controls" "access_logs" {
  # checkov:skip=CKV2_AWS_65: CloudFront standard logging (legacy logging_config) requires ACL-compatible S3 destination buckets
  count  = var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "access_logs" {
  count  = var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.access_logs,
    aws_s3_bucket_public_access_block.access_logs
  ]
}

# Block public access
resource "aws_s3_bucket_public_access_block" "access_logs" {
  count  = var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count  = var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: Expire logs after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count  = var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    expiration {
      days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Policy to allow Log Delivery
resource "aws_s3_bucket_policy" "access_logs" {
  count  = var.enable_observability ? 1 : 0
  bucket = aws_s3_bucket.access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

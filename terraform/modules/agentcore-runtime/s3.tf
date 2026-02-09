# S3 bucket for deployment artifacts
resource "aws_s3_bucket" "deployment" {
  count  = var.deployment_bucket_name == "" ? 1 : 0
  bucket = "${var.agent_name}-deployment-${data.aws_caller_identity.current.account_id}"

  tags = var.tags
}

# S3 versioning
resource "aws_s3_bucket_versioning" "deployment" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = local.deployment_bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 server-side encryption - Using AWS-managed encryption (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "deployment" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = local.deployment_bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # AWS-managed encryption (SSE-S3)
    }
    bucket_key_enabled = true
  }
}

# Block public access to deployment bucket
resource "aws_s3_bucket_public_access_block" "deployment" {
  bucket = local.deployment_bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch log group for packaging
resource "aws_cloudwatch_log_group" "packaging" {
  count = var.enable_packaging ? 1 : 0

  name              = "/aws/bedrock/agentcore/packaging/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# CloudWatch log group for runtime
resource "aws_cloudwatch_log_group" "runtime" {
  count = var.enable_runtime ? 1 : 0

  name              = "/aws/bedrock/agentcore/runtime/${var.agent_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

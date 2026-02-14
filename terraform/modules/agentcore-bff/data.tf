# Session Store (DynamoDB)
# Stores strict server-side sessions. Tokens NEVER touch the browser.
resource "aws_dynamodb_table" "sessions" {
  count = var.enable_bff ? 1 : 0

  name         = "agentcore-sessions-${var.agent_name}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true # AWS Managed
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

# SPA Hosting (S3)
resource "aws_s3_bucket" "spa" {
  count = var.enable_bff ? 1 : 0

  bucket = var.spa_bucket_name != "" ? var.spa_bucket_name : "agentcore-spa-${var.agent_name}-${var.environment}"

  tags = var.tags
}

# Strict Security: Block all public access
resource "aws_s3_bucket_public_access_block" "spa" {
  count = var.enable_bff ? 1 : 0

  bucket = aws_s3_bucket.spa[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spa" {
  count = var.enable_bff ? 1 : 0

  bucket = aws_s3_bucket.spa[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Origin Access Control (CloudFront -> S3)
resource "aws_cloudfront_origin_access_control" "spa" {
  count = var.enable_bff ? 1 : 0

  name                              = "agentcore-spa-oac-${var.agent_name}"
  description                       = "OAC for AgentCore SPA"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_caller_identity" "current" {}

# Bucket Policy: Allow CloudFront
data "aws_iam_policy_document" "spa_access" {
  count = var.enable_bff ? 1 : 0

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.spa[0].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.bff[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  count = var.enable_bff ? 1 : 0

  bucket = aws_s3_bucket.spa[0].id
  policy = data.aws_iam_policy_document.spa_access[0].json
}

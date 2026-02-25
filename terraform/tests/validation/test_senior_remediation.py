import sys


def test_s3_lifecycle():
    print("[Senior Test 1] Verifying S3 Lifecycle Configuration...")
    s3_tf_path = "terraform/modules/agentcore-runtime/s3.tf"
    with open(s3_tf_path, "r") as f:
        content = f.read()
        if "aws_s3_bucket_lifecycle_configuration" not in content:
            raise Exception("FAILED: S3 lifecycle configuration missing")
        if "expiration {" not in content or "days = 90" not in content:
            raise Exception("FAILED: 90-day expiration rule missing")
        if "noncurrent_version_expiration" not in content:
            raise Exception("FAILED: Versioning expiration missing")
    print("  PASS: S3 Lifecycle protection verified.")


def test_api_throttling():
    print("[Senior Test 2] Verifying API Gateway Throttling...")
    apigw_tf_path = "terraform/modules/agentcore-bff/apigateway.tf"
    with open(apigw_tf_path, "r") as f:
        content = f.read()
        if "throttling_burst_limit = 100" not in content:
            raise Exception("FAILED: API burst limit missing or incorrect")
        if "throttling_rate_limit  = 50" not in content:
            raise Exception("FAILED: API rate limit missing or incorrect")
    print("  PASS: API Throttling protection verified.")


def test_spa_cache_headers():
    print("[Senior Test 3] Verifying CloudFront cache/origin request policy strategy...")
    cf_tf_path = "terraform/modules/agentcore-bff/cloudfront.tf"
    with open(cf_tf_path, "r") as f:
        content = f.read()
        if "default_cache_behavior {" not in content:
            raise Exception("FAILED: Default cache behavior block not found")
        if 'name = "Managed-CachingDisabled"' not in content:
            raise Exception("FAILED: Managed CloudFront CachingDisabled policy lookup missing")
        if "cache_policy_id  = data.aws_cloudfront_cache_policy.caching_disabled.id" not in content:
            raise Exception("FAILED: SPA default behavior is not wired to explicit disabled cache policy")
        if "forwarded_values {" in content:
            raise Exception("FAILED: Legacy forwarded_values blocks still present (expected explicit policies)")
        if "default_ttl            = 0" in content or "default_ttl = 0" in content:
            raise Exception("FAILED: Legacy TTL fields still present (expected cache policy usage)")
        if 'origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id' not in content:
            raise Exception("FAILED: API/auth origin request policy wiring missing")
    print("  PASS: CloudFront policy-based cache strategy verified.")


def test_alarm_actions():
    print("[Senior Test 4] Verifying CloudWatch Alarm Actions...")
    obs_tf_path = "terraform/modules/agentcore-foundation/observability.tf"
    with open(obs_tf_path, "r") as f:
        content = f.read()
        if "alarm_actions       = var.alarm_sns_topic_arn" not in content:
            raise Exception("FAILED: Alarm actions not configured with SNS topic variable")
    print("  PASS: Alarm notification infrastructure verified.")


def test_python_logging_hygiene():
    print("[Senior Test 5] Verifying Python Logging Hygiene...")
    auth_src_path = "terraform/modules/agentcore-bff/src/auth_handler.py"
    with open(auth_src_path, "r") as f:
        content = f.read()
        if "import logging" not in content:
            raise Exception("FAILED: logging module not imported in auth_handler.py")
        if "print(" in content:
            raise Exception("FAILED: print() statements still exist in auth_handler.py")
    print("  PASS: Python structured logging verified.")


def test_apigw_access_logs():
    print("[Senior Test 6] Verifying APIGW Access Logging...")
    apigw_tf_path = "terraform/modules/agentcore-bff/apigateway.tf"
    data_tf_path = "terraform/modules/agentcore-bff/data.tf"

    with open(data_tf_path, "r") as f:
        if "aws_cloudwatch_log_group" not in f.read():
            raise Exception("FAILED: APIGW log group not found in data.tf")

    with open(apigw_tf_path, "r") as f:
        content = f.read()
        if "access_log_settings {" not in content:
            raise Exception("FAILED: access_log_settings missing from API Gateway Stage")
        if "tenantId" not in content or "appId" not in content:
            raise Exception("FAILED: tenant/app dimensions missing from access log format")

    print("  PASS: APIGW Access Logging verified.")


def test_cloudfront_spa_api_behavior_split():
    print("[Senior Test 7] Verifying CloudFront SPA/API behavior split hardening...")
    cf_tf_path = "terraform/modules/agentcore-bff/cloudfront.tf"
    with open(cf_tf_path, "r") as f:
        content = f.read()
        if 'resource "aws_cloudfront_function" "spa_route_rewrite"' not in content:
            raise Exception("FAILED: SPA route rewrite CloudFront Function missing")
        if "function_association {" not in content or "event_type   = \"viewer-request\"" not in content:
            raise Exception("FAILED: SPA viewer-request function association missing")
        if "uri.indexOf(\"/api/\") === 0" not in content or "uri.indexOf(\"/auth/\") === 0" not in content:
            raise Exception("FAILED: SPA rewrite function does not preserve /api or /auth paths")
        if "custom_error_response {" in content:
            raise Exception("FAILED: distribution-wide custom_error_response SPA fallback still present")

    print("  PASS: CloudFront SPA/API behavior split hardening verified.")


def test_s3_access_logging():
    print("[Senior Test 8] Verifying Centralized S3 Access Logging...")
    foundation_s3_path = "terraform/modules/agentcore-foundation/s3.tf"
    runtime_s3_path = "terraform/modules/agentcore-runtime/s3.tf"
    bff_data_path = "terraform/modules/agentcore-bff/data.tf"

    with open(foundation_s3_path, "r") as f:
        content = f.read()
        if 'resource "aws_s3_bucket" "access_logs"' not in content:
            raise Exception("FAILED: Centralized logging bucket missing from foundation")
        if '"logging.s3.amazonaws.com"' not in content:
            raise Exception("FAILED: S3 logging service principal missing from bucket policy")
        if 'resource "aws_s3_bucket_ownership_controls" "access_logs"' not in content:
            raise Exception("FAILED: Foundation logging bucket ownership controls missing (CloudFront logging ACL compatibility)")
        if 'object_ownership = "BucketOwnerPreferred"' not in content:
            raise Exception("FAILED: ACL-compatible ownership mode missing for logging buckets")
        if 'resource "aws_s3_bucket_acl" "access_logs"' not in content:
            raise Exception("FAILED: Foundation logging bucket ACL resource missing (CloudFront logging compatibility)")

    with open(runtime_s3_path, "r") as f:
        if 'resource "aws_s3_bucket_logging" "deployment"' not in f.read():
            raise Exception("FAILED: Access logging missing from deployment bucket")

    with open(bff_data_path, "r") as f:
        content = f.read()
        if 'resource "aws_s3_bucket_logging" "spa"' not in content:
            raise Exception("FAILED: Access logging missing from SPA bucket")
        if 'resource "aws_s3_bucket_ownership_controls" "spa"' not in content:
            raise Exception("FAILED: SPA bucket ownership controls missing (CloudFront logging fallback compatibility)")
        if 'resource "aws_s3_bucket_acl" "spa"' not in content:
            raise Exception("FAILED: SPA bucket ACL resource missing (CloudFront logging fallback compatibility)")

    print("  PASS: Centralized S3 Access Logging verified.")


if __name__ == "__main__":
    try:
        test_s3_lifecycle()
        test_api_throttling()
        test_spa_cache_headers()
        test_alarm_actions()
        test_python_logging_hygiene()
        test_apigw_access_logs()
        test_cloudfront_spa_api_behavior_split()
        test_s3_access_logging()
        print("\nAll Senior Engineer operational tests PASSED successfully.")
    except Exception as e:
        print("\nSENIOR OPERATIONAL TEST FAILED: " + str(e))
        sys.exit(1)

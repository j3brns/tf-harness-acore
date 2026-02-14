import os
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
    print("[Senior Test 3] Verifying SPA Caching Strategy...")
    cf_tf_path = "terraform/modules/agentcore-bff/cloudfront.tf"
    with open(cf_tf_path, "r") as f:
        content = f.read()
        if "default_cache_behavior {" not in content:
            raise Exception("FAILED: Default cache behavior block not found")
        if "default_ttl            = 0" not in content:
            raise Exception("FAILED: Index.html caching is enabled (TTL > 0)")
    print("  PASS: SPA cache strategy (immediate refresh) verified.")

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

if __name__ == "__main__":
    try:
        test_s3_lifecycle()
        test_api_throttling()
        test_spa_cache_headers()
        test_alarm_actions()
        test_python_logging_hygiene()
        test_apigw_access_logs()
        print("\nAll Senior Engineer operational tests PASSED successfully.")
    except Exception as e:
        print("\nSENIOR OPERATIONAL TEST FAILED: " + str(e))
        sys.exit(1)

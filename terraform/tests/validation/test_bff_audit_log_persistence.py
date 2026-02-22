import sys


def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def test_bff_module_audit_resources():
    print("[Audit Test 1] Verifying BFF audit Glue/Athena resources...")
    content = _read("terraform/modules/agentcore-bff/audit_logs.tf")

    required = [
        'resource "aws_glue_catalog_database" "bff_audit_logs"',
        'resource "aws_glue_catalog_table" "bff_audit_logs"',
        'resource "aws_athena_workgroup" "bff_audit_logs"',
        'serialization_library = "org.openx.data.jsonserde.JsonSerDe"',
        'encryption_option = "SSE_S3"',
    ]
    for needle in required:
        if needle not in content:
            raise Exception(f"FAILED: Missing expected audit resource/config: {needle}")

    print("  PASS: Glue/Athena audit resources present and SSE-S3 enforced.")


def test_bff_proxy_shadow_s3_write():
    print("[Audit Test 2] Verifying proxy shadow JSON S3 write path...")
    content = _read("terraform/modules/agentcore-bff/src/proxy.js")

    required = [
        "@aws-sdk/client-s3",
        "PutObjectCommand",
        "AUDIT_LOGS_ENABLED",
        "AUDIT_LOGS_BUCKET",
        "AUDIT_LOGS_PREFIX",
        "persistAuditLog",
        "app_id",
        "tenant_id",
        "response_preview_truncated",
        "ServerSideEncryption: \"AES256\"",
    ]
    for needle in required:
        if needle not in content:
            raise Exception(f"FAILED: Proxy audit persistence missing marker: {needle}")

    if "access_token" in content and "audit" in content:
        # We intentionally read access_token for upstream auth. Ensure we are not storing it in the audit record.
        if "access_token:" in content or "accessToken:" in content:
            raise Exception("FAILED: access token appears to be serialized into proxy structures")

    print("  PASS: Proxy writes shadow audit JSON to S3 without token serialization markers.")


def test_bff_proxy_iam_and_env_wiring():
    print("[Audit Test 3] Verifying proxy IAM and env wiring for audit persistence...")
    iam_content = _read("terraform/modules/agentcore-bff/iam.tf")
    lambda_content = _read("terraform/modules/agentcore-bff/lambda.tf")
    vars_content = _read("terraform/modules/agentcore-bff/variables.tf")
    root_vars_content = _read("terraform/variables_bff.tf")
    root_main_content = _read("terraform/main.tf")
    root_outputs_content = _read("terraform/outputs.tf")

    if '"s3:PutObject"' not in iam_content:
        raise Exception("FAILED: Proxy IAM policy missing s3:PutObject for audit logs")
    if "AUDIT_LOGS_BUCKET" not in lambda_content or "AUDIT_LOGS_ENABLED" not in lambda_content:
        raise Exception("FAILED: Proxy Lambda environment missing audit log variables")
    if 'variable "enable_audit_log_persistence"' not in vars_content:
        raise Exception("FAILED: BFF module audit persistence toggle missing")
    if 'variable "enable_bff_audit_log_persistence"' not in root_vars_content:
        raise Exception("FAILED: Root BFF audit persistence toggle missing")
    if "enable_audit_log_persistence = var.enable_bff_audit_log_persistence" not in root_main_content:
        raise Exception("FAILED: Root main.tf does not pass audit persistence toggle to BFF module")
    if "agentcore_bff_audit_logs_athena_workgroup" not in root_outputs_content:
        raise Exception("FAILED: Root outputs missing Athena audit workgroup output")

    print("  PASS: IAM/env/root wiring for BFF audit persistence verified.")


if __name__ == "__main__":
    try:
        test_bff_module_audit_resources()
        test_bff_proxy_shadow_s3_write()
        test_bff_proxy_iam_and_env_wiring()
        print("\nBFF audit log persistence validation tests PASSED.")
    except Exception as e:
        print(f"\nBFF AUDIT LOG PERSISTENCE TEST FAILED: {e}")
        sys.exit(1)

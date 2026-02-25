from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


def _read(rel_path: str) -> str:
    return (REPO_ROOT / rel_path).read_text(encoding="utf-8")


def test_bff_checkov_intentional_default_skips_are_explicit_and_scoped():
    apigw_tf = _read("terraform/modules/agentcore-bff/apigateway.tf")
    cloudfront_tf = _read("terraform/modules/agentcore-bff/cloudfront.tf")
    data_tf = _read("terraform/modules/agentcore-bff/data.tf")

    assert "checkov:skip=CKV_AWS_237" in apigw_tf
    assert "Intentional harness default" in apigw_tf
    assert "checkov:skip=CKV_AWS_120" in apigw_tf
    assert "checkov:skip=CKV_AWS_225" in apigw_tf
    assert apigw_tf.count("checkov:skip=CKV_AWS_59") == 2
    assert apigw_tf.count("checkov:skip=CKV2_AWS_53") == 9
    assert "Rule 14.1 tenant-scope checks" in apigw_tf

    for method_name in (
        "create_tenant",
        "suspend_tenant",
        "rotate_tenant_credentials",
        "fetch_tenant_audit_summary",
        "fetch_tenant_diagnostics",
        "fetch_tenant_timeline",
    ):
        assert f'resource "aws_api_gateway_method" "{method_name}" {{\n  # checkov:skip=CKV2_AWS_53:' in apigw_tf

    assert "checkov:skip=CKV_AWS_310" in cloudfront_tf
    assert "checkov:skip=CKV_AWS_374" in cloudfront_tf
    assert "Intentional harness default" in cloudfront_tf

    assert "checkov:skip=CKV_AWS_119" in data_tf
    assert "ADR-0008" in data_tf


def test_bff_readme_documents_issue_78_classification_and_issue_79_hardening_handoff():
    readme = _read("terraform/modules/agentcore-bff/README.md")

    assert "## Checkov Classification (Issue #78)" in readme
    assert "CKV_AWS_119" in readme
    assert "CKV_AWS_120" in readme
    assert "CKV_AWS_225" in readme
    assert "CKV_AWS_237" in readme
    assert "CKV_AWS_59" in readme
    assert "CKV2_AWS_53" in readme
    assert "CKV_AWS_310" in readme
    assert "CKV_AWS_374" in readme
    assert "#91" in readme
    assert "#79" in readme
    assert "CKV_AWS_86" in readme
    assert "CKV_AWS_50" in readme
    assert "CKV_AWS_272" in readme


def test_bff_cloudfront_access_logging_is_explicitly_configurable_with_default_enabled():
    module_vars = _read("terraform/modules/agentcore-bff/variables.tf")
    module_locals = _read("terraform/modules/agentcore-bff/locals.tf")
    cloudfront_tf = _read("terraform/modules/agentcore-bff/cloudfront.tf")
    root_vars = _read("terraform/variables_bff.tf")
    root_main = _read("terraform/main.tf")
    readme = _read("terraform/modules/agentcore-bff/README.md")

    assert 'variable "enable_cloudfront_access_logging"' in module_vars
    assert 'variable "cloudfront_access_logs_prefix"' in module_vars
    assert "cloudfront_access_logs_prefix must be non-empty" in module_vars

    assert "cloudfront_access_logging_enabled = var.enable_bff && var.enable_cloudfront_access_logging" in module_locals
    assert "trimsuffix(trimspace(var.cloudfront_access_logs_prefix), \"/\")" in module_locals

    assert 'dynamic "logging_config"' in cloudfront_tf
    assert "for_each = local.cloudfront_access_logging_enabled ? [1] : []" in cloudfront_tf

    assert 'variable "enable_bff_cloudfront_access_logging"' in root_vars
    assert 'variable "bff_cloudfront_access_logs_prefix"' in root_vars
    assert "bff_cloudfront_access_logs_prefix must be non-empty" in root_vars

    assert "enable_cloudfront_access_logging = var.enable_bff_cloudfront_access_logging" in root_main
    assert "cloudfront_access_logs_prefix    = var.bff_cloudfront_access_logs_prefix" in root_main

    assert "## Optional CloudFront Access Logging (Issue #64)" in readme
    assert "Delivery semantics" in readme

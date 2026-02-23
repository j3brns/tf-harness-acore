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
    assert "CKV_AWS_310" in readme
    assert "CKV_AWS_374" in readme
    assert "#79" in readme
    assert "CKV_AWS_86" in readme
    assert "CKV_AWS_50" in readme
    assert "CKV_AWS_272" in readme

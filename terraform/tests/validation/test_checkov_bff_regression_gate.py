import importlib.util
from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT_PATH = REPO_ROOT / "terraform/scripts/ci/checkov_bff_regression_gate.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("checkov_bff_regression_gate", SCRIPT_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _payload(failed_checks):
    return {"results": {"failed_checks": failed_checks}}


def _finding(check_id: str, resource: str, file_path: str = "/modules/agentcore-bff/test.tf"):
    return {"check_id": check_id, "resource": resource, "file_path": file_path}


def test_gate_passes_when_bff_findings_match_expected_baseline():
    gate = _load_module()
    payload = _payload(
        [
            _finding("CKV_AWS_86", "module.agentcore_bff.aws_cloudfront_distribution.bff"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.auth_handler"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.authorizer"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.proxy"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.auth_handler"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.authorizer"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.proxy"),
            _finding("CKV_AWS_999", "module.agentcore_foundation.aws_s3_bucket.example"),
        ]
    )

    result = gate.evaluate_bff_regression(gate.extract_bff_findings(payload))

    assert result.ok is True
    assert result.unexpected == ()
    assert result.missing_expected == ()


def test_gate_fails_on_unexpected_bff_finding_and_reports_it():
    gate = _load_module()
    payload = _payload(
        [
            _finding("CKV_AWS_86", "module.agentcore_bff.aws_cloudfront_distribution.bff"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.auth_handler"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.authorizer"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.proxy"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.auth_handler"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.authorizer"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.proxy"),
            _finding("CKV_AWS_123", "module.agentcore_bff.aws_api_gateway_stage.bff"),
        ]
    )

    result = gate.evaluate_bff_regression(gate.extract_bff_findings(payload))
    summary = gate.format_result(result)

    assert result.ok is False
    assert ("CKV_AWS_123", "module.agentcore_bff.aws_api_gateway_stage.bff") in result.unexpected
    assert "Unexpected BFF failures (regression):" in summary


def test_gate_fails_when_expected_baseline_drifts():
    gate = _load_module()
    payload = _payload(
        [
            _finding("CKV_AWS_86", "module.agentcore_bff.aws_cloudfront_distribution.bff"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.auth_handler"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.authorizer"),
            _finding("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.proxy"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.auth_handler"),
            _finding("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.authorizer"),
        ]
    )

    result = gate.evaluate_bff_regression(gate.extract_bff_findings(payload))
    summary = gate.format_result(result)

    assert result.ok is False
    assert ("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.proxy") in result.missing_expected
    assert "Expected baseline failures missing (baseline drift):" in summary

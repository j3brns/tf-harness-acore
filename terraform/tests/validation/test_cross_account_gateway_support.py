from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


def _read(rel_path: str) -> str:
    return (REPO_ROOT / rel_path).read_text(encoding="utf-8")


def test_foundation_gateway_role_invoke_permissions_are_least_privilege():
    content = _read("terraform/modules/agentcore-foundation/iam.tf")

    assert '"lambda:InvokeFunction"' in content
    assert "gateway_target_lambda_arns" in content
    assert "Resource = local.gateway_target_lambda_arns" in content

    lambda_block_start = content.index('"lambda:InvokeFunction"')
    lambda_block_window = content[max(0, lambda_block_start - 300) : lambda_block_start + 500]
    assert 'Resource = "*"' not in lambda_block_window, "Lambda invoke statement must not use wildcard resources"


def test_root_supports_explicit_bff_runtime_role_override_for_cross_account():
    main_tf = _read("terraform/main.tf")
    vars_bff_tf = _read("terraform/variables_bff.tf")

    assert 'var.bff_agentcore_runtime_role_arn != ""' in main_tf
    assert 'variable "bff_agentcore_runtime_role_arn"' in vars_bff_tf
    assert "valid IAM role ARN" in vars_bff_tf


def test_root_exposes_gateway_outputs_for_cross_account_policy_wiring():
    outputs_tf = _read("terraform/outputs.tf")

    assert 'output "agentcore_gateway_arn"' in outputs_tf
    assert 'output "agentcore_gateway_role_arn"' in outputs_tf

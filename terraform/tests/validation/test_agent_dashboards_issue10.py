from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


def _read(rel_path: str) -> str:
    return (REPO_ROOT / rel_path).read_text(encoding="utf-8")


def test_foundation_module_defines_agent_dashboard_resource_and_inputs():
    foundation_vars = _read("terraform/modules/agentcore-foundation/variables.tf")
    observability_tf = _read("terraform/modules/agentcore-foundation/observability.tf")
    foundation_outputs = _read("terraform/modules/agentcore-foundation/outputs.tf")

    for token in [
        'variable "enable_agent_dashboards"',
        'variable "agent_dashboard_name"',
        'variable "dashboard_region"',
        'variable "dashboard_widgets_override"',
    ]:
        assert token in foundation_vars

    assert 'resource "aws_cloudwatch_dashboard" "agent"' in observability_tf
    assert "dashboard_include_runtime_logs" in observability_tf
    assert "/aws/bedrock/agentcore/runtime/" in observability_tf
    assert "/aws/bedrock/agentcore/gateway/" in observability_tf

    assert 'output "agent_dashboard_name"' in foundation_outputs
    assert 'output "agent_dashboard_console_url"' in foundation_outputs


def test_root_wires_dashboard_settings_and_exposes_outputs():
    root_main = _read("terraform/main.tf")
    root_vars = _read("terraform/variables.tf")
    root_outputs = _read("terraform/outputs.tf")

    for token in [
        'variable "enable_agent_dashboards"',
        'variable "agent_dashboard_name"',
        'variable "dashboard_region"',
        'variable "dashboard_widgets_override"',
    ]:
        assert token in root_vars

    assert "enable_agent_dashboards" in root_main
    assert "dashboard_include_code_interpreter_logs" in root_main
    assert "dashboard_include_evaluator_logs" in root_main

    for token in [
        'output "agentcore_dashboard_name"',
        'output "agentcore_dashboard_console_url"',
        'output "agentcore_inference_profile_arn"',
    ]:
        assert token in root_outputs


def test_docs_cover_dashboard_usage_and_inference_profile_cost_isolation():
    readme = _read("README.md")
    tfvars_example = _read("terraform/terraform.tfvars.example")
    docs_tf = _read("docs/terraform.md")

    assert "Per-Agent Dashboards (Issue #10)" in readme
    assert "use the created **application inference profile ARN as `modelId`**" in readme
    assert "enable_agent_dashboards = false" in tfvars_example
    assert "Use the application inference profile ARN as modelId" in tfvars_example

    assert "input_enable_agent_dashboards" in docs_tf
    assert "output_agentcore_dashboard_console_url" in docs_tf
    assert "output_agentcore_inference_profile_arn" in docs_tf

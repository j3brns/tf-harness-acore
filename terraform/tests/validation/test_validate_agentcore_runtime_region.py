from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


def _load_module():
    script_path = Path(__file__).resolve().parents[2] / "scripts" / "validate_agentcore_runtime_region.py"
    spec = importlib.util.spec_from_file_location("validate_agentcore_runtime_region", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def test_parse_simple_tfvars_reads_top_level_region_assignments(tmp_path):
    tfvars = tmp_path / "example.tfvars"
    tfvars.write_text(
        "\n".join(
            [
                'region = "eu-west-2"',
                'agentcore_region = ""',
                'bff_region = "eu-central-1" # comment',
                "tags = {",
                '  Team = "Platform"',
                "}",
            ]
        ),
        encoding="utf-8",
    )

    values = mod.parse_simple_tfvars(tfvars)

    assert values["region"] == "eu-west-2"
    assert values["agentcore_region"] == ""
    assert values["bff_region"] == "eu-central-1"
    assert "tags" not in values


def test_resolve_regions_uses_region_when_agentcore_region_override_is_empty(tmp_path):
    tfvars = tmp_path / "region-only.tfvars"
    tfvars.write_text('region = "eu-central-1"\nagentcore_region = ""\n', encoding="utf-8")

    args = mod.parse_args(["--tfvars", str(tfvars)])
    resolved = mod.resolve_regions(args)

    assert resolved.region == "eu-central-1"
    assert resolved.agentcore_region == "eu-central-1"
    assert resolved.agentcore_region_source == "region"
    assert resolved.bff_region == "eu-central-1"


def test_run_validation_rejects_runtime_matrix_region_without_endpoint_deployability():
    resolved = mod.ResolvedRegions(
        region="eu-west-2",
        agentcore_region="eu-west-2",
        bff_region="eu-west-2",
        agentcore_region_source="region",
        config_path=None,
    )

    code, lines = mod.run_validation(resolved)
    output = "\n".join(lines)

    assert code == 1
    assert "AgentCore Runtime region deployability guard failed" in output
    assert "eu-west-2" in output
    assert "feature-region matrix" in output
    assert "eu-central-1, eu-west-1" in output


def test_run_validation_accepts_endpoint_confirmed_runtime_region():
    resolved = mod.ResolvedRegions(
        region="eu-central-1",
        agentcore_region="eu-central-1",
        bff_region="eu-central-1",
        agentcore_region_source="region",
        config_path=None,
    )

    code, lines = mod.run_validation(resolved)
    output = "\n".join(lines)

    assert code == 0
    assert output.startswith("OK: AgentCore Runtime region deployability guard passed")
    assert "checked 2026-02-25" in output
    assert mod.GENERAL_REFERENCE_URL in output
    assert mod.AGENTCORE_REGIONS_URL in output


def test_main_reports_cross_region_bff_warning(tmp_path, capsys):
    tfvars = tmp_path / "split.tfvars"
    tfvars.write_text(
        "\n".join(
            [
                'region = "eu-central-1"',
                'agentcore_region = ""',
                'bff_region = "eu-west-2"',
            ]
        ),
        encoding="utf-8",
    )

    code = mod.main(["--tfvars", str(tfvars)])
    captured = capsys.readouterr()

    assert code == 0
    assert "WARNING: bff_region resolves to eu-west-2" in captured.out
    assert "Config source:" in captured.out

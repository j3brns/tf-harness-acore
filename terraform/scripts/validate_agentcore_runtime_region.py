#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

CHECK_DATE = "2026-02-25"
GENERAL_REFERENCE_URL = "https://docs.aws.amazon.com/general/latest/gr/bedrock_agentcore.html"
AGENTCORE_REGIONS_URL = "https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html"

# AWS General Reference (AgentCore endpoints and quotas), checked 2026-02-25 via AWS Knowledge MCP.
GENERAL_REF_CONTROL_PLANE_REGIONS = frozenset(
    {
        "us-east-1",
        "us-east-2",
        "us-west-2",
        "ap-southeast-1",
        "ap-southeast-2",
        "ap-south-1",
        "ap-northeast-1",
        "eu-west-1",
        "eu-central-1",
    }
)

# AWS General Reference AgentCore data plane endpoint regions, same check date/source as above.
GENERAL_REF_DATA_PLANE_REGIONS = frozenset(
    {
        "us-east-1",
        "us-east-2",
        "us-west-2",
        "ap-southeast-1",
        "ap-southeast-2",
        "ap-south-1",
        "ap-northeast-1",
        "eu-west-1",
        "eu-central-1",
    }
)

# AgentCore Runtime feature matrix from the AgentCore Developer Guide, checked 2026-02-25 via AWS Knowledge MCP.
AGENTCORE_RUNTIME_MATRIX_REGIONS = frozenset(
    {
        "us-east-1",
        "us-east-2",
        "us-west-2",
        "eu-central-1",
        "eu-west-1",
        "eu-west-2",
        "eu-west-3",
        "eu-north-1",
        "ap-south-1",
        "ap-southeast-1",
        "ap-southeast-2",
        "ap-northeast-1",
        "ap-northeast-2",
        "ca-central-1",
    }
)

RECOMMENDED_EU_RUNTIME_DEPLOYABLE_REGIONS = ("eu-central-1", "eu-west-1")
REGION_CODE_RE = re.compile(r"^[a-z]{2}(?:-[a-z]+)+-\d+$")
TFVARS_STRING_ASSIGNMENT_RE = re.compile(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^\s#]+))\s*(?:#.*)?$'
)
TRACKED_TFVARS_KEYS = frozenset({"region", "agentcore_region", "bff_region"})


@dataclass(frozen=True)
class ResolvedRegions:
    region: str | None
    agentcore_region: str | None
    bff_region: str | None
    agentcore_region_source: str | None
    config_path: Path | None


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate AgentCore Runtime deployability for the configured region before Terraform plan/apply."
    )
    parser.add_argument(
        "--tfvars",
        type=Path,
        help="Path to a Terraform tfvars file. If omitted, terraform/terraform.tfvars is used when present.",
    )
    parser.add_argument("--region", help="Override for Terraform variable 'region'.")
    parser.add_argument("--agentcore-region", help="Override for Terraform variable 'agentcore_region'.")
    parser.add_argument("--bff-region", help="Override for Terraform variable 'bff_region'.")
    parser.add_argument(
        "--quiet-success",
        action="store_true",
        help="Suppress the success banner (warnings/errors still print).",
    )
    return parser.parse_args(argv)


def default_tfvars_path() -> Path:
    return Path(__file__).resolve().parents[1] / "terraform.tfvars"


def parse_simple_tfvars(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        match = TFVARS_STRING_ASSIGNMENT_RE.match(raw_line)
        if not match:
            continue
        key = match.group(1)
        if key not in TRACKED_TFVARS_KEYS:
            continue
        quoted_value = match.group(2)
        bare_value = match.group(3)
        value = quoted_value if quoted_value is not None else (bare_value or "")
        values[key] = value
    return values


def _clean_region_value(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _effective_agentcore_region(region: str | None, agentcore_region: str | None) -> tuple[str | None, str | None]:
    if agentcore_region:
        return agentcore_region, "agentcore_region"
    if region:
        return region, "region"
    return None, None


def _effective_bff_region(agentcore_region: str | None, bff_region: str | None) -> str | None:
    if bff_region:
        return bff_region
    return agentcore_region


def resolve_regions(args: argparse.Namespace) -> ResolvedRegions:
    config_path: Path | None = None
    tfvars_values: dict[str, str] = {}

    tfvars_path = args.tfvars
    if tfvars_path is None:
        default_path = default_tfvars_path()
        if default_path.exists():
            tfvars_path = default_path

    if tfvars_path is not None:
        config_path = tfvars_path
        if not tfvars_path.exists():
            raise FileNotFoundError(f"tfvars file not found: {tfvars_path}")
        tfvars_values = parse_simple_tfvars(tfvars_path)

    region = _clean_region_value(args.region) or _clean_region_value(tfvars_values.get("region"))
    agentcore_region_override = _clean_region_value(args.agentcore_region) or _clean_region_value(
        tfvars_values.get("agentcore_region")
    )
    effective_agentcore_region, agentcore_source = _effective_agentcore_region(region, agentcore_region_override)
    bff_region_override = _clean_region_value(args.bff_region) or _clean_region_value(tfvars_values.get("bff_region"))
    effective_bff_region = _effective_bff_region(effective_agentcore_region, bff_region_override)

    return ResolvedRegions(
        region=region,
        agentcore_region=effective_agentcore_region,
        bff_region=effective_bff_region,
        agentcore_region_source=agentcore_source,
        config_path=config_path,
    )


def validate_region_code(value: str, field_name: str) -> list[str]:
    if REGION_CODE_RE.match(value):
        return []
    return [f"{field_name} '{value}' is not a valid AWS region code format"]


def _sources_block() -> list[str]:
    return [
        f"Sources (checked {CHECK_DATE}):",
        f"  - AWS General Reference (AgentCore endpoints): {GENERAL_REFERENCE_URL}",
        f"  - AgentCore supported Regions matrix: {AGENTCORE_REGIONS_URL}",
    ]


def run_validation(resolved: ResolvedRegions) -> tuple[int, list[str]]:
    lines: list[str] = []

    if resolved.agentcore_region is None:
        lines.append(
            "SKIP: AgentCore Runtime region deployability check skipped (no region or agentcore_region resolved)."
        )
        if resolved.config_path is None:
            lines.append(
                "  Provide --tfvars <path> or --region/--agentcore-region (Makefile: make validate-region TFVARS=...)"
            )
        else:
            lines.append(f"  Parsed config file: {resolved.config_path}")
        lines.extend(_sources_block())
        return 0, lines

    format_errors = []
    format_errors.extend(validate_region_code(resolved.agentcore_region, "effective agentcore_region"))
    if resolved.region:
        format_errors.extend(validate_region_code(resolved.region, "region"))
    if resolved.bff_region:
        format_errors.extend(validate_region_code(resolved.bff_region, "effective bff_region"))
    if format_errors:
        lines.append("ERROR: AgentCore Runtime region deployability guard failed (invalid region input).")
        for err in format_errors:
            lines.append(f"  - {err}")
        lines.extend(_sources_block())
        return 1, lines

    target = resolved.agentcore_region
    has_control_endpoint = target in GENERAL_REF_CONTROL_PLANE_REGIONS
    has_data_endpoint = target in GENERAL_REF_DATA_PLANE_REGIONS
    in_runtime_matrix = target in AGENTCORE_RUNTIME_MATRIX_REGIONS

    if not (has_control_endpoint and has_data_endpoint):
        missing = []
        if not has_control_endpoint:
            missing.append("control plane endpoint")
        if not has_data_endpoint:
            missing.append("data plane endpoint")

        lines.append("ERROR: AgentCore Runtime region deployability guard failed.")
        lines.append(
            f"  Effective agentcore_region: {target}"
            + (f" (derived from {resolved.agentcore_region_source})" if resolved.agentcore_region_source else "")
        )
        lines.append(
            "  This repo requires AWS General Reference coverage for both AgentCore control plane and data plane endpoints"
            " before Terraform plan/apply."
        )
        lines.append(f"  Missing endpoint coverage: {', '.join(missing)}")
        if in_runtime_matrix:
            lines.append(
                "  Note: AgentCore Runtime appears in the AgentCore feature-region matrix for this region, but the"
                " endpoint deployability requirement above still fails."
            )
        else:
            lines.append("  The AgentCore Runtime feature-region matrix also does not list this region.")
        lines.append(
            "  Recommended EU deployable regions for this repo: " + ", ".join(RECOMMENDED_EU_RUNTIME_DEPLOYABLE_REGIONS)
        )
        lines.append(
            "  Current deployable AgentCore Runtime regions (endpoint-confirmed): "
            + ", ".join(sorted(GENERAL_REF_CONTROL_PLANE_REGIONS & GENERAL_REF_DATA_PLANE_REGIONS))
        )
        if resolved.bff_region and resolved.bff_region != target:
            lines.append(
                f"  Config note: bff_region resolves to {resolved.bff_region}; cross-region BFF/runtime splits are"
                " supported but increase latency and separate observability footprints."
            )
        lines.extend(_sources_block())
        return 1, lines

    lines.append(
        "OK: AgentCore Runtime region deployability guard passed for "
        f"{target} (control + data plane endpoints confirmed; checked {CHECK_DATE})."
    )
    if not in_runtime_matrix:
        lines.append(
            "WARNING: Endpoint coverage is present, but AgentCore Runtime is not listed in the current feature matrix."
            " Re-check AWS docs before deployment."
        )
    if resolved.bff_region and resolved.bff_region != target:
        lines.append(
            f"WARNING: bff_region resolves to {resolved.bff_region} while agentcore_region is {target}"
            " (cross-region split)."
        )
    if resolved.config_path is not None:
        lines.append(f"Config source: {resolved.config_path}")
    lines.extend(_sources_block())
    return 0, lines


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        resolved = resolve_regions(args)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return 1

    code, lines = run_validation(resolved)
    if code == 0 and args.quiet_success and lines and lines[0].startswith("OK:"):
        for line in lines[1:]:
            print(line)
        return 0

    for line in lines:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())

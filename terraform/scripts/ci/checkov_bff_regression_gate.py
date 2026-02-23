#!/usr/bin/env python3
"""Fail CI only on unexpected BFF Checkov regressions."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


BFF_RESOURCE_PREFIX = "module.agentcore_bff."

# Temporary approved baseline for the behavior-changing hardening work tracked in #79.
EXPECTED_BFF_FAILURE_PAIRS: tuple[tuple[str, str], ...] = (
    ("CKV_AWS_86", "module.agentcore_bff.aws_cloudfront_distribution.bff"),
    ("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.auth_handler"),
    ("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.authorizer"),
    ("CKV_AWS_50", "module.agentcore_bff.aws_lambda_function.proxy"),
    ("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.auth_handler"),
    ("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.authorizer"),
    ("CKV_AWS_272", "module.agentcore_bff.aws_lambda_function.proxy"),
)


@dataclass(frozen=True)
class Finding:
    check_id: str
    resource: str
    file_path: str

    @property
    def pair(self) -> tuple[str, str]:
        return (self.check_id, self.resource)


@dataclass(frozen=True)
class GateResult:
    bff_findings: tuple[Finding, ...]
    unexpected: tuple[tuple[str, str], ...]
    missing_expected: tuple[tuple[str, str], ...]

    @property
    def ok(self) -> bool:
        return not self.unexpected and not self.missing_expected


def _failed_checks(payload: dict[str, Any]) -> list[dict[str, Any]]:
    results = payload.get("results")
    if not isinstance(results, dict):
        raise ValueError("Checkov JSON missing 'results' object")
    failed_checks = results.get("failed_checks")
    if failed_checks is None:
        return []
    if not isinstance(failed_checks, list):
        raise ValueError("Checkov JSON field 'results.failed_checks' is not a list")
    return [entry for entry in failed_checks if isinstance(entry, dict)]


def extract_bff_findings(payload: dict[str, Any]) -> tuple[Finding, ...]:
    findings: list[Finding] = []
    for item in _failed_checks(payload):
        resource = str(item.get("resource", "") or "")
        if not resource.startswith(BFF_RESOURCE_PREFIX):
            continue
        findings.append(
            Finding(
                check_id=str(item.get("check_id", "") or ""),
                resource=resource,
                file_path=str(item.get("file_path", "") or item.get("file_abs_path", "") or ""),
            )
        )
    return tuple(sorted(findings, key=lambda f: (f.check_id, f.resource, f.file_path)))


def evaluate_bff_regression(findings: tuple[Finding, ...]) -> GateResult:
    actual_counter = Counter(f.pair for f in findings)
    expected_counter = Counter(EXPECTED_BFF_FAILURE_PAIRS)

    unexpected = tuple(sorted((actual_counter - expected_counter).elements()))
    missing_expected = tuple(sorted((expected_counter - actual_counter).elements()))

    return GateResult(
        bff_findings=findings,
        unexpected=unexpected,
        missing_expected=missing_expected,
    )


def format_result(result: GateResult) -> str:
    lines: list[str] = [
        "BFF Checkov Regression Gate",
        f"Observed BFF failed findings: {len(result.bff_findings)}",
        f"Expected BFF failed findings baseline (#79): {len(EXPECTED_BFF_FAILURE_PAIRS)}",
    ]

    if result.bff_findings:
        lines.append("")
        lines.append("Observed BFF failures:")
        for finding in result.bff_findings:
            lines.append(f"  - {finding.check_id} | {finding.resource} ({finding.file_path})")

    if result.unexpected:
        lines.append("")
        lines.append("Unexpected BFF failures (regression):")
        for check_id, resource in result.unexpected:
            lines.append(f"  - {check_id} | {resource}")

    if result.missing_expected:
        lines.append("")
        lines.append("Expected baseline failures missing (baseline drift):")
        lines.append("  Update the baseline in this script when #79 intentionally changes the remaining BFF hardening set.")
        for check_id, resource in result.missing_expected:
            lines.append(f"  - {check_id} | {resource}")

    lines.append("")
    lines.append(
        "PASS: BFF Checkov failures match the approved #79 hardening baseline."
        if result.ok
        else "FAIL: BFF Checkov failures differ from the approved #79 hardening baseline."
    )
    return "\n".join(lines)


def load_checkov_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"Input file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Path to Checkov JSON output")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        payload = load_checkov_json(Path(args.input))
        result = evaluate_bff_regression(extract_bff_findings(payload))
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    print(format_result(result))
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

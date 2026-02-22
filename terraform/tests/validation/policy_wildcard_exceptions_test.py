#!/usr/bin/env python3
"""Conformance check for IAM wildcard resource exceptions.

This script enforces repo policy for `Resource = "*"` in Terraform:
- New wildcard resources must be explicitly reviewed (count/classification check).
- AWS-required wildcard exceptions must include an `AWS-REQUIRED:` comment.
- The workload identity wildcard must remain ABAC-scoped and documented.

Runs with stdlib only (no pytest dependency required).
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path


EXPECTED_COUNTS = {
    "ec2_network_interface": 2,
    "logs_put_resource_policy": 1,
    "bedrock_abac_scoped": 1,
}

WINDOW_LINES = 25
WILDCARD_RE = re.compile(r'Resource\s*=\s*"\*"')


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def classify_wildcard(window_text: str) -> str | None:
    if '"ec2:CreateNetworkInterface"' in window_text:
        return "ec2_network_interface"
    if '"logs:PutResourcePolicy"' in window_text:
        return "logs_put_resource_policy"
    if '"bedrock:*"' in window_text:
        return "bedrock_abac_scoped"
    return None


def validate_documentation(
    classification: str, window_text: str, rel_path: str, line_no: int, errors: list[str]
) -> None:
    prefix = f"{rel_path}:{line_no}"
    if classification == "ec2_network_interface":
        expected_comment = "# AWS-REQUIRED: EC2 network interface APIs do not support resource-level scoping."
        if expected_comment not in window_text:
            errors.append(f"{prefix}: missing required wildcard exception comment ({expected_comment})")
        return

    if classification == "logs_put_resource_policy":
        expected_comment = "# AWS-REQUIRED: logs:PutResourcePolicy does not support resource-level scoping"
        if expected_comment not in window_text:
            errors.append(f"{prefix}: missing required wildcard exception comment ({expected_comment})")
        return

    if classification == "bedrock_abac_scoped":
        if "# Rule 7.2: Resource-level ABAC" not in window_text:
            errors.append(f"{prefix}: missing ABAC rationale comment for workload identity wildcard")
        if '"aws:ResourceTag/Project"' not in window_text:
            errors.append(f"{prefix}: workload identity wildcard missing ABAC tag condition")
        return

    errors.append(f"{prefix}: unhandled wildcard classification {classification}")


def main() -> int:
    root = repo_root()
    terraform_dir = root / "terraform"
    if not terraform_dir.exists():
        print(f"ERROR: Terraform directory not found: {terraform_dir}")
        return 1

    findings: list[tuple[str, int, str]] = []
    errors: list[str] = []

    for tf_file in sorted(terraform_dir.rglob("*.tf")):
        if ".terraform" in tf_file.parts:
            continue
        rel_path = tf_file.relative_to(root).as_posix()
        lines = tf_file.read_text(encoding="utf-8").splitlines()
        for idx, line in enumerate(lines):
            if not WILDCARD_RE.search(line):
                continue
            start = max(0, idx - WINDOW_LINES)
            end = min(len(lines), idx + WINDOW_LINES + 1)
            window_text = "\n".join(lines[start:end])
            classification = classify_wildcard(window_text)
            line_no = idx + 1
            if classification is None:
                errors.append(f'{rel_path}:{line_no}: wildcard Resource="*" is not an approved/documented exception')
                continue
            findings.append((rel_path, line_no, classification))
            validate_documentation(classification, window_text, rel_path, line_no, errors)

    counts = Counter(classification for _, _, classification in findings)
    total_expected = sum(EXPECTED_COUNTS.values())

    print("==========================================")
    print("IAM Wildcard Exception Conformance Check")
    print("==========================================")
    for rel_path, line_no, classification in findings:
        print(f"  FOUND: {rel_path}:{line_no} -> {classification}")

    if len(findings) != total_expected:
        errors.append(
            f'Expected {total_expected} wildcard Resource="*" statements, found {len(findings)}. '
            "Review/test update required for policy exception changes."
        )

    for classification, expected_count in EXPECTED_COUNTS.items():
        actual_count = counts.get(classification, 0)
        if actual_count != expected_count:
            errors.append(
                f"Expected {expected_count} '{classification}' wildcard exceptions, found {actual_count}. "
                "Review/test update required."
            )

    print("")
    print("Counts:")
    for classification in sorted(EXPECTED_COUNTS):
        print(f"  {classification}: {counts.get(classification, 0)}")

    if errors:
        print("")
        print("FAIL:")
        for err in errors:
            print(f"  - {err}")
        return 1

    print("")
    print('PASS: All wildcard Resource="*" usages are approved and documented.')
    return 0


if __name__ == "__main__":
    sys.exit(main())

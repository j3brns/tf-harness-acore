#!/usr/bin/env python3
"""Generate policy and tag conformance report for Bedrock AgentCore.

This script scans the Terraform codebase to inventory IAM wildcard exceptions
and verify canonical tag taxonomy compliance, producing a Markdown report.

Workstream B: Tag + Policy Consolidation (Issue #61)
"""

import re
import sys
from collections import Counter
from pathlib import Path
from datetime import datetime

# --- Configuration ---

EXPECTED_WILDCARDS = {
    "ec2_network_interface": 2,
    "logs_put_resource_policy": 1,
    "bedrock_abac_scoped": 1,
    "s3_list_all_my_buckets": 1,
}

REQUIRED_TAGS = ["AppID", "Environment", "AgentName", "ManagedBy", "Owner"]

WINDOW_LINES = 25
WILDCARD_RE = re.compile(r'Resource\s*=\s*"\*"')

# --- Helper Functions ---

def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]

def classify_wildcard(window_text: str) -> str | None:
    if '"ec2:CreateNetworkInterface"' in window_text:
        return "ec2_network_interface"
    if '"logs:PutResourcePolicy"' in window_text:
        return "logs_put_resource_policy"
    if '"bedrock:*"' in window_text:
        return "bedrock_abac_scoped"
    if '"s3:ListAllMyBuckets"' in window_text:
        return "s3_list_all_my_buckets"
    return None

def get_rationale(window_text: str) -> str:
    match = re.search(r'#\s*(AWS-REQUIRED:.*|Rule 14\.3 ABAC.*)', window_text)
    if match:
        return match.group(1).strip()
    return "MISSING RATIONALE"

def check_tags_locals(root: Path) -> dict:
    locals_file = root / "terraform" / "locals.tf"
    if not locals_file.exists():
        return {"status": "FAIL", "reason": "locals.tf not found"}
    
    content = locals_file.read_text()
    results = {}
    for tag in REQUIRED_TAGS:
        results[tag] = tag in content
    
    all_present = all(results.values())
    return {
        "status": "PASS" if all_present else "FAIL",
        "details": results
    }

def check_tags_versions(root: Path) -> dict:
    versions_file = root / "terraform" / "versions.tf"
    if not versions_file.exists():
        return {"status": "FAIL", "reason": "versions.tf not found"}
    
    content = versions_file.read_text()
    results = {}
    for tag in REQUIRED_TAGS:
        results[tag] = tag in content
    
    all_present = all(results.values())
    return {
        "status": "PASS" if all_present else "FAIL",
        "details": results
    }

# --- Main Logic ---

def main():
    root = repo_root()
    terraform_dir = root / "terraform"
    examples_dir = root / "examples" / "mcp-servers" / "terraform"
    report_path = root / "docs" / "POLICY_CONFORMANCE_REPORT.md"

    findings = []
    errors = []

    # 1. Scan for IAM Wildcards
    search_dirs = [terraform_dir, examples_dir]
    for search_dir in search_dirs:
        if not search_dir.exists():
            continue
        for tf_file in sorted(search_dir.rglob("*.tf")):
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
                rationale = get_rationale(window_text)
                line_no = idx + 1
                
                compliant = classification is not None and "MISSING RATIONALE" not in rationale
                findings.append({
                    "file": rel_path,
                    "line": line_no,
                    "type": classification or "UNKNOWN",
                    "rationale": rationale,
                    "compliant": compliant
                })
                
                if not compliant:
                    errors.append(f"Non-compliant wildcard at {rel_path}:{line_no}")

    # 2. Check Tag Conformance
    tag_locals = check_tags_locals(root)
    tag_versions = check_tags_versions(root)

    # 3. Generate Report
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    report = []
    report.append("# Policy Conformance Report")
    report.append(f"*Generated on: {now}*")
    report.append("")
    report.append("## Executive Summary")
    
    overall_compliant = len(errors) == 0 and tag_locals["status"] == "PASS" and tag_versions["status"] == "PASS"
    status_icon = "✅" if overall_compliant else "❌"
    report.append(f"**Overall Status**: {status_icon} {'COMPLIANT' if overall_compliant else 'NON-COMPLIANT'}")
    report.append("")
    
    report.append("### Inventory Summary")
    wildcard_counts = Counter(f["type"] for f in findings)
    report.append("| Exception Type | Count | Expected | Status |")
    report.append("|----------------|-------|----------|--------|")
    for w_type, expected in EXPECTED_WILDCARDS.items():
        actual = wildcard_counts.get(w_type, 0)
        status = "✅" if actual == expected else "⚠️"
        report.append(f"| {w_type} | {actual} | {expected} | {status} |")
    
    # Handle unexpected/unknown types
    for w_type in wildcard_counts:
        if w_type not in EXPECTED_WILDCARDS:
            report.append(f"| {w_type} | {wildcard_counts[w_type]} | 0 | ❌ |")
    
    report.append("")
    report.append("## Detailed IAM Wildcard Inventory")
    report.append("| File | Line | Classification | Rationale | Status |")
    report.append("|------|------|----------------|-----------|--------|")
    for f in findings:
        status = "✅" if f["compliant"] else "❌"
        report.append(f"| `{f['file']}` | {f['line']} | {f['type']} | {f['rationale']} | {status} |")
    
    report.append("")
    report.append("## Tag Taxonomy Conformance")
    report.append("Standardized tags: `AppID`, `Environment`, `AgentName`, `ManagedBy`, `Owner`.")
    report.append("")
    report.append("| Check | Status | Details |")
    report.append("|-------|--------|---------|")
    
    def format_details(details):
        return ", ".join([f"{k}: {'✅' if v else '❌'}" for k, v in details.items()])

    report.append(f"| `locals.tf` canonical_tags | {tag_locals['status']} | {format_details(tag_locals.get('details', {}))} |")
    report.append(f"| `versions.tf` default_tags | {tag_versions['status']} | {format_details(tag_versions.get('details', {}))} |")
    
    report.append("")
    report.append("---")
    report.append("*Note: This report is automatically generated. Any deviations must be approved via the Exception Change Control process documented in GEMINI.md.*")

    report_path.write_text("\n".join(report))
    print(f"Report generated at: {report_path}")
    
    return 0 if overall_compliant else 1

if __name__ == "__main__":
    sys.exit(main())

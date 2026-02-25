#!/usr/bin/env python3
"""SDK Version Drift Report for Strands and AgentCore.

This script scans example and template pyproject.toml files to identify
version drift across key SDK dependencies.

Developer Experience (DX) - Issue #114
"""

import argparse
import os
import re
from pathlib import Path
import tomllib
from datetime import datetime
import sys

# --- Configuration ---

# Packages we care about tracking for version drift
TRACKED_PACKAGES = [
    "bedrock-agentcore",
    "strands-agents",
    "strands-agents-tools",
    "strands-deep-agents",
    "linkup-sdk",
    "bedrock-agentcore-starter-toolkit",
]

# --- Helper Functions ---

def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]

def extract_versions_from_toml(toml_content):
    """Extract versions for tracked packages from a pyproject.toml dictionary."""
    versions = {}
    
    # Check dependencies
    dependencies = toml_content.get("project", {}).get("dependencies", [])
    for dep in dependencies:
        for package in TRACKED_PACKAGES:
            # Match package name followed by version specifier
            # Handle both exact matches and variants like strands-agents[otel]
            pattern = rf"^{package}(\[.*\])?([>=<].*)$"
            match = re.match(pattern, dep)
            if match:
                versions[package] = match.group(2)
                
    # Check optional-dependencies
    optional_deps = toml_content.get("project", {}).get("optional-dependencies", {})
    for group, deps in optional_deps.items():
        for dep in deps:
            for package in TRACKED_PACKAGES:
                pattern = rf"^{package}(\[.*\])?([>=<].*)$"
                match = re.match(pattern, dep)
                if match:
                    if package not in versions:
                        versions[package] = match.group(2)
                        
    return versions

def extract_versions_from_jinja(content):
    """
    Crude extraction for jinja templates.
    """
    versions = {}
    for package in TRACKED_PACKAGES:
        # Match "package>=version" or "package==version"
        pattern = rf'"{package}(\[.*\])?([>=<].*)"'
        match = re.search(pattern, content)
        if match:
            versions[package] = match.group(2)
    return versions

# --- Main Logic ---

def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate SDK version drift report.")
    parser.add_argument("--output", type=Path, help="Path to write the Markdown report.")
    args = parser.parse_args(argv)

    root = repo_root()
    examples_dir = root / "examples"
    templates_dir = root / "templates"
    
    report_data = {}
    
    # 1. Scan examples
    for pyproject in sorted(examples_dir.glob("**/pyproject.toml")):
        if ".terraform" in pyproject.parts:
            continue
        rel_path = pyproject.relative_to(root).as_posix()
        try:
            with open(pyproject, "rb") as f:
                data = tomllib.load(f)
                versions = extract_versions_from_toml(data)
                if versions:
                    report_data[rel_path] = versions
        except Exception as e:
            print(f"Warning: Failed to parse {rel_path}: {e}", file=sys.stderr)

    # 2. Scan templates
    for jinja in sorted(templates_dir.glob("**/pyproject.toml.jinja")):
        rel_path = jinja.relative_to(root).as_posix()
        try:
            content = jinja.read_text(encoding="utf-8")
            versions = extract_versions_from_jinja(content)
            if versions:
                report_data[rel_path] = versions
        except Exception as e:
            print(f"Warning: Failed to parse {rel_path}: {e}", file=sys.stderr)

    # 3. Analyze drift
    all_packages = set()
    for path, versions in report_data.items():
        all_packages.update(versions.keys())
    
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    report = []
    report.append("# SDK Version Drift Report")
    report.append(f"*Generated on: {now}*")
    report.append("")
    report.append("This report tracks version consistency for Strands and AgentCore SDKs across examples and templates.")
    report.append("")
    
    drift_found = False
    
    report.append("## Executive Summary")
    summary_table = ["| Package | Status | Unique Versions |", "|---------|--------|-----------------|"]
    
    detailed_sections = []
    
    for package in sorted(all_packages):
        package_versions = {}
        for path, versions in report_data.items():
            if package in versions:
                v = versions[package]
                if v not in package_versions:
                    package_versions[v] = []
                package_versions[v].append(path)
        
        status = "✅ CONSISTENT"
        if len(package_versions) > 1:
            status = "⚠️ DRIFTED"
            drift_found = True
        
        summary_table.append(f"| {package} | {status} | {len(package_versions)} |")
        
        detailed_sections.append(f"### {package}")
        detailed_sections.append("| Version | Files |")
        detailed_sections.append("|---------|-------|")
        for v, paths in sorted(package_versions.items()):
            files_list = "<br>".join([f"`{p}`" for p in paths])
            detailed_sections.append(f"| `{v}` | {files_list} |")
        detailed_sections.append("")

    report.extend(summary_table)
    report.append("")
    report.append("## Detailed Package Inventory")
    report.extend(detailed_sections)
    
    report.append("---")
    report.append("*Note: This report is automatically generated. Any planned version drift must be documented in the corresponding execution issue.*")

    report_content = "\n".join(report)
    
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report_content, encoding="utf-8")
        print(f"Report generated at: {args.output}")
    else:
        print(report_content)

    return 1 if drift_found else 0

if __name__ == "__main__":
    sys.exit(main())

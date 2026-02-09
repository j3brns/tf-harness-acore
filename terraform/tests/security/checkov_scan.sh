#!/bin/bash
# Checkov Security Scan
# Scans Terraform code for security and compliance issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

echo "=========================================="
echo "Running Checkov security scan"
echo "=========================================="

cd "$TERRAFORM_DIR"

# Check if checkov is installed
if ! command -v checkov &> /dev/null; then
    echo "ERROR: checkov not found. Install with: pip install checkov"
    exit 1
fi

# Run Checkov scan
echo ""
echo "Scanning Terraform configuration..."

checkov -d "$TERRAFORM_DIR" \
    --framework terraform \
    --quiet \
    --compact \
    --output cli \
    --config-file "$TERRAFORM_DIR/.checkov.yaml" \
    --output json:"$TERRAFORM_DIR/checkov_results.json"

# Check results
if [ -f "$TERRAFORM_DIR/checkov_results.json" ]; then
    PASSED=$(jq '.summary.passed' "$TERRAFORM_DIR/checkov_results.json" 2>/dev/null || echo "0")
    FAILED=$(jq '.summary.failed' "$TERRAFORM_DIR/checkov_results.json" 2>/dev/null || echo "0")
    SKIPPED=$(jq '.summary.skipped' "$TERRAFORM_DIR/checkov_results.json" 2>/dev/null || echo "0")

    echo ""
    echo "=========================================="
    echo "Checkov Results Summary"
    echo "=========================================="
    echo "Passed:  $PASSED"
    echo "Failed:  $FAILED"
    echo "Skipped: $SKIPPED"
    echo "=========================================="

    # Fail if critical issues found
    if [ "$FAILED" != "0" ] && [ "$FAILED" != "null" ]; then
        echo ""
        echo "FAIL: Found $FAILED security issues"
        echo "Review checkov_results.json for details"
        echo ""
        echo "Failed checks:"
        jq -r '.results.failed_checks[]? | "  - \(.check_id): \(.check_result.evaluated_keys[0])"' "$TERRAFORM_DIR/checkov_results.json" 2>/dev/null || true
        exit 1
    fi

    echo ""
    echo "PASS: No critical security issues found"
    rm -f "$TERRAFORM_DIR/checkov_results.json"
else
    echo "PASS: Checkov scan completed (no output file)"
fi

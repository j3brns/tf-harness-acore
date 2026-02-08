#!/bin/bash
# Checkov Security Scan
# Scans Terraform code for security and compliance issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=========================================="
echo "Running Checkov security scan"
echo "=========================================="

cd "$PROJECT_DIR"

# Check if checkov is installed
if ! command -v checkov &> /dev/null; then
    echo "ERROR: checkov not found. Install with: pip install checkov"
    exit 1
fi

# Run Checkov scan
echo ""
echo "Scanning Terraform configuration..."

checkov -d . \
    --framework terraform \
    --quiet \
    --compact \
    --output cli \
    --output json:checkov_results.json

# Check results
if [ -f "checkov_results.json" ]; then
    PASSED=$(jq '.summary.passed' checkov_results.json 2>/dev/null || echo "0")
    FAILED=$(jq '.summary.failed' checkov_results.json 2>/dev/null || echo "0")
    SKIPPED=$(jq '.summary.skipped' checkov_results.json 2>/dev/null || echo "0")

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
        jq -r '.results.failed_checks[]? | "  - \(.check_id): \(.check_result.evaluated_keys[0])"' checkov_results.json 2>/dev/null || true
        exit 1
    fi

    echo ""
    echo "PASS: No critical security issues found"
    rm -f checkov_results.json
else
    echo "PASS: Checkov scan completed (no output file)"
fi

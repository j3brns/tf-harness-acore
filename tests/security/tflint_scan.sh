#!/bin/bash
# TFLint Scan
# Checks Terraform code for best practices and potential errors

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=========================================="
echo "Running TFLint scan"
echo "=========================================="

cd "$PROJECT_DIR"

# Check if tflint is installed
if ! command -v tflint &> /dev/null; then
    echo "ERROR: tflint not found. Install from: https://github.com/terraform-linters/tflint"
    exit 1
fi

# Initialize TFLint plugins
echo ""
echo "Initializing TFLint..."
tflint --init

# Run TFLint on root module
echo ""
echo "Scanning root module..."
tflint --format compact

# Run TFLint on each submodule
echo ""
echo "Scanning submodules..."
for module_dir in modules/agentcore-*; do
    if [ -d "$module_dir" ]; then
        echo "  Scanning: $module_dir"
        tflint --chdir="$module_dir" --format compact
    fi
done

echo ""
echo "=========================================="
echo "TFLint scan completed - PASSED"
echo "=========================================="

#!/bin/bash
# TFLint Scan
# Checks Terraform code for best practices and potential errors

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

echo "=========================================="
echo "Running TFLint scan"
echo "=========================================="

cd "$TERRAFORM_DIR"

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
CONFIG_FILE="$TERRAFORM_DIR/.tflint.hcl"
tflint --format compact --config "$CONFIG_FILE"

# Run TFLint on each submodule
echo ""
echo "Scanning submodules..."
for module_dir in "$TERRAFORM_DIR"/modules/agentcore-*; do
    if [ -d "$module_dir" ]; then
        echo "  Scanning: $module_dir"
        tflint --chdir="$module_dir" --format compact --config "$CONFIG_FILE"
    fi
done

echo ""
echo "=========================================="
echo "TFLint scan completed - PASSED"
echo "=========================================="

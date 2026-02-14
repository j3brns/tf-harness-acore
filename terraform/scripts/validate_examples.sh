#!/bin/bash
# Example Configuration Validation
# Validates all example tfvars files

set -e

# Robust path detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"
EXAMPLES_DIR="$REPO_ROOT/examples"

echo "=========================================="
echo "Validating example configurations"
echo "  Root: $REPO_ROOT"
echo "  Terraform: $TERRAFORM_DIR"
echo "  Examples: $EXAMPLES_DIR"
echo "=========================================="

cd "$TERRAFORM_DIR"

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
export PATH=$PATH:/usr/local/bin
if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform command not found in PATH"
    exit 1
fi
terraform init -backend=false -input=false

# Counter and tracking
EXAMPLE_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

validate_example() {
    local example_file=$1
    local example_name=$(basename "$example_file")

    echo ""
    echo "Testing: $example_name"
    echo "  File: $example_file"

    # Validate syntax with plan
    set +e
    local output
    output=$(AWS_EC2_METADATA_DISABLED=true terraform plan -var-file="$example_file" -input=false -out="test-${example_name}.tfplan" 2>&1)
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        echo "  PASS: Plan generated successfully"
        rm -f "test-${example_name}.tfplan"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    elif echo "$output" | grep -qE "No valid credential sources found|failed to refresh cached credentials"; then
        echo "  SKIP: AWS credentials not available for plan"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return 0
    else
        echo "  FAIL: Plan failed for $example_file"
        echo "$output"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

# Find all .tfvars and .tfvars.example files in subdirectories
echo "Scanning for configuration files in $EXAMPLES_DIR subdirectories..."
if [ -d "$EXAMPLES_DIR" ]; then
    # Use a robust find command with escaped parentheses, excluding mcp-servers
    FILES=$(find "$EXAMPLES_DIR" -maxdepth 3 -not -path "*/mcp-servers/*" \( -name "*.tfvars" -o -name "*.tfvars.example" \))

    if [ -z "$FILES" ]; then
        echo "WARN: No .tfvars or .tfvars.example files found in $EXAMPLES_DIR"
    else
        echo "Found configurations:"
        echo "$FILES"
        for example_file in $FILES; do
            EXAMPLE_COUNT=$((EXAMPLE_COUNT + 1))
            # Don't let a single failure stop the script, so we can see the summary
            validate_example "$example_file" || true
        done
    fi
else
    echo "WARN: Examples directory not found: $EXAMPLES_DIR"
fi

echo ""
echo "=========================================="
echo "Example Validation Summary"
echo "=========================================="
echo "Total:  $EXAMPLE_COUNT"
echo "Passed: $PASS_COUNT"
echo "Skipped: $SKIP_COUNT"
echo "Failed: $FAIL_COUNT"
echo "=========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "FAIL: Some examples failed validation"
    exit 1
fi

if [ "$EXAMPLE_COUNT" -eq 0 ]; then
    echo "WARN: No example configurations found"
    exit 0
fi

echo "All examples validated successfully"

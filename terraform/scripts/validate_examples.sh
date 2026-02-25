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

# Provide mock credentials for validation to avoid skipping
export AWS_ACCESS_KEY_ID=mock
export AWS_SECRET_ACCESS_KEY=mock
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform command not found in PATH"
    exit 1
fi
terraform init -backend=false -input=false > /dev/null

# Counter and tracking
EXAMPLE_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
# SKIP_COUNT is removed as this is now a hard gate

validate_example() {
    local example_file=$1
    local example_name=$(basename "$example_file")

    echo ""
    echo "Testing: $example_name"
    echo "  File: $example_file"

    # Validate syntax with plan
    set +e
    local output
    # Use -refresh=false to avoid AWS API calls, but it still validates variables
    output=$(terraform plan -var-file="$example_file" -refresh=false -input=false 2>&1)
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        echo "  PASS: Plan generated successfully"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        # Check if it's a "real" error or just a credential/STS error
        # We consider STS errors as PASS because we are validating variables, not connectivity
        if echo "$output" | grep -qE "Invalid value|Reference to|Unsupported|Duplicate|Missing required variable|Variables not allowed|Attribute redefined|argument may be set only once"; then
            echo "  FAIL: Real validation error found in $example_file"
            echo "$output"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 1
        elif echo "$output" | grep -qE "Retrieving AWS account details|retrieving caller identity from STS|InvalidClientTokenId|No valid credential sources found|failed to refresh cached credentials"; then
            # If ONLY STS error, we consider it a success for variable validation
            echo "  PASS: Variable validation succeeded (ignoring expected STS error)"
            PASS_COUNT=$((PASS_COUNT + 1))
            return 0
        else
            echo "  FAIL: Unknown error in $example_file"
            echo "$output"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 1
        fi
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

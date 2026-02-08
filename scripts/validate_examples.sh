#!/bin/bash
# Example Configuration Validation
# Validates all example tfvars files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Validating example configurations"
echo "=========================================="

cd "$PROJECT_DIR"

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
terraform init -backend=false -input=false

# Find and validate each example
EXAMPLES_DIR="examples"
EXAMPLE_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

validate_example() {
    local example_file=$1
    local example_name=$(basename "$example_file" .tfvars)

    echo ""
    echo "Testing: $example_name"
    echo "  File: $example_file"

    # Validate syntax with plan
    if terraform plan -var-file="$example_file" -input=false -out="test-${example_name}.tfplan" 2>&1; then
        echo "  PASS: Plan generated successfully"
        rm -f "test-${example_name}.tfplan"
        ((PASS_COUNT++))
        return 0
    else
        echo "  FAIL: Plan failed for $example_file"
        ((FAIL_COUNT++))
        return 1
    fi
}

# Process all .tfvars files in examples directory
if [ -d "$EXAMPLES_DIR" ]; then
    for example_file in "$EXAMPLES_DIR"/*.tfvars; do
        if [ -f "$example_file" ]; then
            ((EXAMPLE_COUNT++))
            validate_example "$example_file"
        fi
    done
else
    echo "WARN: Examples directory not found: $EXAMPLES_DIR"
fi

# Process example subdirectories (e.g., examples/1-hello-world/terraform.tfvars)
for example_dir in "$EXAMPLES_DIR"/*/; do
    if [ -d "$example_dir" ]; then
        for tfvars_file in "$example_dir"*.tfvars "$example_dir"terraform.tfvars; do
            if [ -f "$tfvars_file" ]; then
                ((EXAMPLE_COUNT++))
                validate_example "$tfvars_file"
            fi
        done
    fi
done

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

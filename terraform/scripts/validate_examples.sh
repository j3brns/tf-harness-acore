#!/bin/bash
# Example Configuration Validation
# Validates all example tfvars files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

echo "=========================================="
echo "Validating example configurations"
echo "=========================================="

cd "$TERRAFORM_DIR"

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
terraform init -backend=false -input=false

# Find and validate each example
EXAMPLES_DIR="$REPO_ROOT/examples"
EXAMPLE_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
declare -A SEEN_FILES

validate_example() {
    local example_file=$1
    local example_name=$(basename "$example_file" .tfvars)

    echo ""
    echo "Testing: $example_name"
    echo "  File: $example_file"

    # Validate syntax with plan
    set +e
    local output
    output=$(AWS_EC2_METADATA_DISABLED=true terraform -chdir="$TERRAFORM_DIR" plan -var-file="$example_file" -input=false -out="test-${example_name}.tfplan" 2>&1)
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        echo "  PASS: Plan generated successfully"
        rm -f "$TERRAFORM_DIR/test-${example_name}.tfplan"
        ((PASS_COUNT++))
        return 0
    elif echo "$output" | grep -qE "No valid credential sources found|failed to refresh cached credentials"; then
        echo "  SKIP: AWS credentials not available for plan"
        ((SKIP_COUNT++))
        return 0
    else
        echo "  FAIL: Plan failed for $example_file"
        echo "$output"
        ((FAIL_COUNT++))
        return 1
    fi
}

# Process all .tfvars files in examples directory
if [ -d "$EXAMPLES_DIR" ]; then
    for example_file in "$EXAMPLES_DIR"/*.tfvars; do
        if [ -f "$example_file" ]; then
            if [ -z "${SEEN_FILES[$example_file]+x}" ]; then
                SEEN_FILES["$example_file"]=1
                ((EXAMPLE_COUNT++))
                validate_example "$example_file"
            fi
        fi
    done
else
    echo "WARN: Examples directory not found: $EXAMPLES_DIR"
fi

# Process example subdirectories (e.g., examples/1-hello-world/terraform.tfvars)
    for example_dir in "$EXAMPLES_DIR"/*/; do
        if [ -d "$example_dir" ]; then
            for tfvars_file in "$example_dir"terraform.tfvars "$example_dir"*.tfvars; do
                if [ -f "$tfvars_file" ]; then
                    if [ -z "${SEEN_FILES[$tfvars_file]+x}" ]; then
                        SEEN_FILES["$tfvars_file"]=1
                        ((EXAMPLE_COUNT++))
                        validate_example "$tfvars_file"
                    fi
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

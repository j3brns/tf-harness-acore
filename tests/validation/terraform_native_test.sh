#!/bin/bash
# Terraform Native Validation Tests
# Run locally without AWS account

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=========================================="
echo "Running Terraform native validation tests"
echo "=========================================="

cd "$PROJECT_DIR"

# Test 1: Format check
echo ""
echo "[1/4] Checking Terraform formatting..."
if terraform fmt -check -recursive; then
    echo "PASS: All files properly formatted"
else
    echo "FAIL: Some files need formatting. Run: terraform fmt -recursive"
    exit 1
fi

# Test 2: Initialize (no backend)
echo ""
echo "[2/4] Initializing Terraform (no backend)..."
terraform init -backend=false -input=false

# Test 3: Validate syntax
echo ""
echo "[3/4] Validating Terraform syntax..."
if terraform validate; then
    echo "PASS: Terraform configuration is valid"
else
    echo "FAIL: Terraform validation failed"
    exit 1
fi

# Test 4: Plan generation (dry run)
echo ""
echo "[4/4] Generating Terraform plan..."
if [ -f "examples/research-agent.tfvars" ]; then
    terraform plan -var-file="examples/research-agent.tfvars" -input=false -out=test.tfplan
    echo "PASS: Plan generated successfully"
    rm -f test.tfplan
else
    echo "WARN: No example tfvars found, skipping plan test"
fi

# Validate each module individually
echo ""
echo "=========================================="
echo "Validating individual modules..."
echo "=========================================="

for module_dir in modules/agentcore-*; do
    if [ -d "$module_dir" ]; then
        echo ""
        echo "Validating module: $module_dir"
        cd "$PROJECT_DIR/$module_dir"
        terraform init -backend=false -input=false
        terraform validate
        echo "PASS: $module_dir validated"
        cd "$PROJECT_DIR"
    fi
done

echo ""
echo "=========================================="
echo "All Terraform native tests PASSED"
echo "=========================================="

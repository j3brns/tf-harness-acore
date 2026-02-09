#!/bin/bash
# Cedar Policy Syntax Validation
# Validates Cedar policy files for syntax errors

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

echo "=========================================="
echo "Validating Cedar policies"
echo "=========================================="

cd "$TERRAFORM_DIR"

# Find Cedar policy files
POLICY_DIR="$TERRAFORM_DIR/modules/agentcore-governance/cedar_policies"

if [ ! -d "$POLICY_DIR" ]; then
    echo "WARN: Cedar policies directory not found: $POLICY_DIR"
    echo "SKIP: No policies to validate"
    exit 0
fi

# Count policy files
POLICY_COUNT=$(find "$POLICY_DIR" -name "*.cedar" 2>/dev/null | wc -l)

if [ "$POLICY_COUNT" -eq 0 ]; then
    echo "WARN: No .cedar files found in $POLICY_DIR"
    echo "SKIP: No policies to validate"
    exit 0
fi

echo "Found $POLICY_COUNT Cedar policy files"
echo ""

# Check if cedar CLI is available
if command -v cedar &> /dev/null; then
    echo "Using Cedar CLI for validation..."

    for policy in "$POLICY_DIR"/*.cedar; do
        if [ -f "$policy" ]; then
            echo "Validating: $(basename "$policy")"
            cedar validate --policies "$policy" || {
                echo "FAIL: Invalid policy: $policy"
                exit 1
            }
            echo "  PASS"
        fi
    done
else
    echo "WARN: Cedar CLI not installed. Performing basic syntax check..."
    echo "      Install with: cargo install cedar-policy-cli"
    echo ""

    # Basic syntax validation without cedar CLI
    for policy in "$POLICY_DIR"/*.cedar; do
        if [ -f "$policy" ]; then
            echo "Checking: $(basename "$policy")"

            # Check for required Cedar keywords
            if grep -q "permit\|forbid" "$policy"; then
                echo "  Found policy rules"
            else
                echo "  WARN: No permit/forbid rules found"
            fi

            # Check for balanced braces
            OPEN_BRACES=$(grep -o "{" "$policy" | wc -l)
            CLOSE_BRACES=$(grep -o "}" "$policy" | wc -l)

            if [ "$OPEN_BRACES" -eq "$CLOSE_BRACES" ]; then
                echo "  Braces balanced: $OPEN_BRACES pairs"
            else
                echo "  FAIL: Unbalanced braces: $OPEN_BRACES open, $CLOSE_BRACES close"
                exit 1
            fi

            echo "  PASS (basic check)"
        fi
    done
fi

echo ""
echo "=========================================="
echo "Cedar policy validation completed - PASSED"
echo "=========================================="

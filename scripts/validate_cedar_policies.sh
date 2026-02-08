#!/bin/bash
# Validate Cedar policy files
# Usage: ./scripts/validate_cedar_policies.sh
#
# This script validates Cedar policy syntax without requiring AWS credentials.
# It performs:
# 1. Basic syntax validation (brace matching)
# 2. Cedar CLI validation (if installed)
# 3. Policy structure checks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POLICY_DIR="$PROJECT_ROOT/modules/agentcore-governance/cedar_policies"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Validating Cedar Policies"
echo "=========================================="
echo ""

# Check if policy directory exists
if [ ! -d "$POLICY_DIR" ]; then
    echo -e "${YELLOW}No Cedar policies directory found at:${NC}"
    echo "  $POLICY_DIR"
    echo ""
    echo "Skipping Cedar validation."
    exit 0
fi

# Check for Cedar CLI
CEDAR_CLI_AVAILABLE=false
if command -v cedar &> /dev/null; then
    CEDAR_CLI_AVAILABLE=true
    echo -e "${GREEN}Cedar CLI found${NC}"
    cedar --version
else
    echo -e "${YELLOW}Cedar CLI not installed${NC}"
    echo "Install with: cargo install cedar-policy-cli"
    echo "Falling back to basic syntax checks..."
fi
echo ""

# Track results
PASSED=0
FAILED=0
WARNINGS=0

# Find all Cedar policy files
POLICY_FILES=$(find "$POLICY_DIR" -name "*.cedar" -type f 2>/dev/null || true)

if [ -z "$POLICY_FILES" ]; then
    echo -e "${YELLOW}No .cedar files found in $POLICY_DIR${NC}"
    exit 0
fi

for policy in $POLICY_FILES; do
    POLICY_NAME=$(basename "$policy")
    echo -e "${YELLOW}Validating: $POLICY_NAME${NC}"

    # Basic syntax check: Brace matching
    OPEN_BRACES=$(grep -o "{" "$policy" | wc -l)
    CLOSE_BRACES=$(grep -o "}" "$policy" | wc -l)

    if [ "$OPEN_BRACES" -ne "$CLOSE_BRACES" ]; then
        echo -e "  ${RED}✗ Unbalanced braces: { = $OPEN_BRACES, } = $CLOSE_BRACES${NC}"
        FAILED=$((FAILED + 1))
        continue
    else
        echo -e "  ${GREEN}✓ Braces balanced${NC}"
    fi

    # Basic syntax check: Parentheses matching
    OPEN_PARENS=$(grep -o "(" "$policy" | wc -l)
    CLOSE_PARENS=$(grep -o ")" "$policy" | wc -l)

    if [ "$OPEN_PARENS" -ne "$CLOSE_PARENS" ]; then
        echo -e "  ${RED}✗ Unbalanced parentheses: ( = $OPEN_PARENS, ) = $CLOSE_PARENS${NC}"
        FAILED=$((FAILED + 1))
        continue
    else
        echo -e "  ${GREEN}✓ Parentheses balanced${NC}"
    fi

    # Check for required keywords
    if ! grep -qE "^(permit|forbid)" "$policy"; then
        echo -e "  ${YELLOW}⚠ No permit/forbid statement found${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ${GREEN}✓ Policy statement found${NC}"
    fi

    # Check for principal, action, resource
    MISSING_ELEMENTS=()
    if ! grep -q "principal" "$policy"; then
        MISSING_ELEMENTS+=("principal")
    fi
    if ! grep -q "action" "$policy"; then
        MISSING_ELEMENTS+=("action")
    fi
    if ! grep -q "resource" "$policy"; then
        MISSING_ELEMENTS+=("resource")
    fi

    if [ ${#MISSING_ELEMENTS[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}⚠ Missing elements: ${MISSING_ELEMENTS[*]}${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "  ${GREEN}✓ All required elements present${NC}"
    fi

    # If Cedar CLI is available, use it for full validation
    if [ "$CEDAR_CLI_AVAILABLE" = true ]; then
        SCHEMA_FILE="$POLICY_DIR/schema.json"

        if [ -f "$SCHEMA_FILE" ]; then
            # Validate with schema
            if cedar validate --policies "$policy" --schema "$SCHEMA_FILE" 2>/dev/null; then
                echo -e "  ${GREEN}✓ Cedar CLI validation passed (with schema)${NC}"
            else
                echo -e "  ${RED}✗ Cedar CLI validation failed${NC}"
                cedar validate --policies "$policy" --schema "$SCHEMA_FILE" 2>&1 | head -10
                FAILED=$((FAILED + 1))
                continue
            fi
        else
            # Validate without schema
            if cedar validate --policies "$policy" 2>/dev/null; then
                echo -e "  ${GREEN}✓ Cedar CLI validation passed${NC}"
            else
                echo -e "  ${YELLOW}⚠ Cedar CLI validation failed (may need schema)${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    fi

    # Check for common issues
    # 1. Empty conditions
    if grep -qE "when\s*{\s*}" "$policy"; then
        echo -e "  ${YELLOW}⚠ Empty 'when' block found${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi

    # 2. TODO/FIXME comments
    if grep -qiE "(TODO|FIXME|XXX)" "$policy"; then
        echo -e "  ${YELLOW}⚠ TODO/FIXME comment found${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi

    PASSED=$((PASSED + 1))
    echo ""
done

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""
TOTAL=$((PASSED + FAILED))
echo "Policies checked: $TOTAL"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "  ${RED}Failed: $FAILED${NC}"
fi
if [ $WARNINGS -gt 0 ]; then
    echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
fi
echo ""

# Final result
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ All policies valid with $WARNINGS warning(s)${NC}"
    else
        echo -e "${GREEN}✓ All Cedar policies validated successfully${NC}"
    fi
    exit 0
else
    echo -e "${RED}✗ $FAILED policy/policies failed validation${NC}"
    exit 1
fi

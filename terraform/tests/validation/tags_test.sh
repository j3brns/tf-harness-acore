#!/bin/bash
# Canonical Tag Taxonomy Validation (Issue #22, Workstream B)
#
# Verifies that:
#   1. The required canonical tag keys are defined in locals.tf.
#   2. The root variables.tf declares the owner variable.
#   3. The provider default_tags blocks include all canonical keys.
#
# Usage: bash terraform/tests/validation/tags_test.sh
# Requires: no AWS credentials, no terraform init needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"

PASS=0
FAIL=0

check() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -q "$pattern" "$file"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "        Expected pattern '$pattern' in $file"
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo "Canonical Tag Taxonomy Validation"
echo "=========================================="

echo ""
echo "--- locals.tf: canonical_tags local ---"
LOCALS="$TERRAFORM_DIR/locals.tf"
check "canonical_tags local defined"   "canonical_tags"   "$LOCALS"
check "AppID key present"              "AppID"            "$LOCALS"
check "AgentAlias key present"         "AgentAlias"       "$LOCALS"
check "Environment key present"        "Environment"      "$LOCALS"
check "AgentName key present"          "AgentName"        "$LOCALS"
check "ManagedBy key present"          "ManagedBy"        "$LOCALS"
check "Owner key present"              "Owner"            "$LOCALS"

echo ""
echo "--- variables.tf: owner variable ---"
VARS="$TERRAFORM_DIR/variables.tf"
check "owner variable declared"        "variable \"owner\""  "$VARS"

echo ""
echo "--- versions.tf: provider default_tags ---"
VERSIONS="$TERRAFORM_DIR/versions.tf"
check "provider default_tags AppID"    "AppID"   "$VERSIONS"
check "provider default_tags AgentAlias" "AgentAlias" "$VERSIONS"
check "provider default_tags Environment" "Environment" "$VERSIONS"
check "provider default_tags AgentName" "AgentName" "$VERSIONS"
check "provider default_tags ManagedBy" "ManagedBy" "$VERSIONS"
check "provider default_tags Owner"    "Owner"   "$VERSIONS"

echo ""
echo "--- main.tf: canonical_tags passed to all modules ---"
MAIN="$TERRAFORM_DIR/main.tf"
CANONICAL_COUNT=$(grep -c "canonical_tags" "$MAIN" 2>/dev/null || echo 0)
if [ "$CANONICAL_COUNT" -ge 5 ]; then
  echo "  PASS: canonical_tags used in $CANONICAL_COUNT module calls (>= 5 required)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: canonical_tags used in only $CANONICAL_COUNT module calls (>= 5 required)"
  FAIL=$((FAIL + 1))
fi

# Verify no bare var.tags left in module arguments (only in locals merge, which is expected)
RAW_TAG_MODULE_REFS=$(grep -c "tags\s*=\s*var\.tags" "$MAIN" 2>/dev/null || true)
RAW_TAG_MODULE_REFS="${RAW_TAG_MODULE_REFS:-0}"
if [ "$RAW_TAG_MODULE_REFS" -eq 0 ]; then
  echo "  PASS: No bare 'tags = var.tags' in module calls (all use canonical_tags)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Found $RAW_TAG_MODULE_REFS bare 'tags = var.tags' in module calls"
  grep -n "tags\s*=\s*var\.tags" "$MAIN" || true
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "PASS"

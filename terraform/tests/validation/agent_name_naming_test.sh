#!/bin/bash
# Agent identity vs alias naming validation (Issue #16, Workstream B)
#
# Verifies that:
#   1. Terraform enforces the low-collision agent_name pattern.
#   2. Canonical tags expose AgentAlias for human-facing visibility.
#   3. Example tfvars use app_id and compliant internal agent names.
#
# Usage: bash terraform/tests/validation/agent_name_naming_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

PASS=0
FAIL=0

check_grep() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -Eq "$pattern" "$file"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "        Expected pattern '$pattern' in $file"
    FAIL=$((FAIL + 1))
  fi
}

check_agent_name_file() {
  local file="$1"
  local agent_name
  local app_id
  agent_name="$(sed -nE 's/^[[:space:]]*agent_name[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p' "$file" | head -1)"
  app_id="$(sed -nE 's/^[[:space:]]*app_id[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p' "$file" | head -1)"

  if [[ -z "$agent_name" ]]; then
    echo "  FAIL: $file has no agent_name assignment"
    FAIL=$((FAIL + 1))
    return
  fi

  if [[ "$agent_name" =~ ^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+(-[a-z0-9]+)?-[a-z0-9]{4,6}$ ]]; then
    echo "  PASS: $file agent_name matches low-collision pattern ($agent_name)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $file agent_name does not match pattern ($agent_name)"
    FAIL=$((FAIL + 1))
  fi

  if [[ -n "$app_id" ]]; then
    echo "  PASS: $file defines app_id alias ($app_id)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $file is missing app_id alias"
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo "Agent Name + Alias Naming Validation"
echo "=========================================="

echo ""
echo "--- Terraform enforcement ---"
ROOT_VARS="$REPO_ROOT/terraform/variables.tf"
check_grep "root agent_name validation regex includes suffix" "\\[a-z0-9\\]\\{4,6\\}|\\[a-z0-9\\]\\{4,6\\}\\$|\\{4,6\\}" "$ROOT_VARS"
check_grep "root agent_name error message references app_id alias" "Use app_id for the human-facing alias" "$ROOT_VARS"
check_grep "root legacy escape hatch variable declared" "variable \"allow_legacy_agent_name\"" "$ROOT_VARS"
check_grep "root validation documents legacy escape hatch intent" "allow_legacy_agent_name=true only to preserve an existing deployed name" "$ROOT_VARS"

echo ""
echo "--- Canonical tags include AgentAlias ---"
check_grep "locals canonical tags include AgentAlias" "AgentAlias" "$REPO_ROOT/terraform/locals.tf"
check_grep "provider default_tags include AgentAlias" "AgentAlias" "$REPO_ROOT/terraform/versions.tf"

echo ""
echo "--- Examples use alias + compliant internal names ---"
for tfvars in \
  "$REPO_ROOT/examples/1-hello-world/terraform.tfvars" \
  "$REPO_ROOT/examples/2-gateway-tool/terraform.tfvars" \
  "$REPO_ROOT/examples/3-deepresearch/terraform.tfvars" \
  "$REPO_ROOT/examples/4-research/terraform.tfvars" \
  "$REPO_ROOT/examples/research-agent.tfvars"
do
  check_agent_name_file "$tfvars"
done

echo ""
echo "--- Template prompts reflect convention ---"
check_grep "Copier agent_name help mentions internal identity" "Internal agent identity" "$REPO_ROOT/templates/agent-project/copier.yml"
check_grep "Copier agent_name default is suffix-based" "my-agent-core-a1b2" "$REPO_ROOT/templates/agent-project/copier.yml"

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=========================================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi

echo "PASS"

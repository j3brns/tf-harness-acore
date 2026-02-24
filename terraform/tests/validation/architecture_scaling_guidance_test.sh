#!/bin/bash
# Architecture scaling guidance + state segmentation validation
#
# Verifies that docs and CI encode the key scaling controls:
# - segmented Terraform backend keys (env/app/agent) in GitLab CI
# - architecture quota table for major services
# - explicit CloudWatch Logs resource policy "10" correction
# - inference-profile scaling/cost/auth planning note

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

ARCH_DOC="$REPO_ROOT/docs/architecture.md"
GITLAB_CI="$REPO_ROOT/.gitlab-ci.yml"

PASS=0
FAIL=0

check_literal() {
  local label="$1"
  local needle="$2"
  local file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "        Missing literal: $needle"
    echo "        File: $file"
    FAIL=$((FAIL + 1))
  fi
}

check_regex() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  if grep -Eq "$pattern" "$file"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "        Missing pattern: $pattern"
    echo "        File: $file"
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo "Architecture Scaling Guidance Validation"
echo "=========================================="

echo ""
echo "--- CI backend key segmentation ---"
check_literal "segmented mode supported" 'segmented)' "$GITLAB_CI"
check_literal "legacy env-only fallback documented" 'legacy-env-only)' "$GITLAB_CI"
check_literal "segmented key uses env/app/agent pattern" 'TF_STATE_KEY="agentcore/${CI_ENVIRONMENT_NAME}/${TF_STATE_APP_ID_SEGMENT}/${TF_STATE_AGENT_NAME_SEGMENT}/terraform.tfstate"' "$GITLAB_CI"
check_literal "TF_STATE_APP_ID required guard" 'ERROR: TF_STATE_APP_ID is required for segmented backend keys' "$GITLAB_CI"
check_literal "TF_STATE_AGENT_NAME required guard" 'ERROR: TF_STATE_AGENT_NAME is required for segmented backend keys' "$GITLAB_CI"

echo ""
echo "--- Architecture quota table and scaling notes ---"
check_literal "quota planning section present" "### Scaling Parameters and Service Quotas (Planning Inputs)" "$ARCH_DOC"
check_literal "main quotas table heading present" "Main quotas to track (defaults; account/Region unless noted):" "$ARCH_DOC"
check_literal "cloudwatch resource policy quota row present" '| CloudWatch Logs | **Resource policies** | `10` |' "$ARCH_DOC"
check_literal "cloudwatch correction note present" "Important correction: the \`10\` limit commonly encountered in this repo is **CloudWatch Logs resource policies**, not" "$ARCH_DOC"
check_literal "cloud map discoverinstances quota row present" "| AWS Cloud Map | \`DiscoverInstances\` steady rate | \`1,000/s\` |" "$ARCH_DOC"
check_literal "xray segments quota row present" "| AWS X-Ray | Segments per second | \`2,600\` |" "$ARCH_DOC"
check_literal "dynamodb table quota row present" "| DynamoDB | Tables per account/Region (initial) | \`2,500\` |" "$ARCH_DOC"

echo ""
echo "--- Inference profile coverage (cost + auth + scaling note) ---"
check_literal "inference profile architecture section present" "### Cost Allocation and Authorization Boundary (Inference Profiles)" "$ARCH_DOC"
check_literal "inference profile quota planning row present" "| Bedrock (application inference profiles) | Model invocation quotas | Varies by model/region/account |" "$ARCH_DOC"
check_regex "inference profile row explains rollout-time quota check" "throughput/token limits .* checked per target model and region" "$ARCH_DOC"

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"

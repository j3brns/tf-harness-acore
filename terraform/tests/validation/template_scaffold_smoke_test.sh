#!/usr/bin/env bash
# Template scaffold smoke test (fast inner-loop)
#
# Generates one or two Copier scaffolds into .scratch, then runs local-only
# Terraform init/validate and basic render checks. Designed to be cheap enough
# for template iteration without full CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/templates/agent-project"
SMOKE_ROOT="$REPO_ROOT/.scratch/template-smoke"
SMOKE_MODE="${TEMPLATE_SMOKE_MODE:-fast}" # fast|full

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

need_cmd copier
need_cmd terraform
need_cmd python3

if find "$TEMPLATE_DIR" -type f \( -name '*.pyc' -o -path '*/__pycache__/*' \) | grep -q .; then
  echo "ERROR: template contains compiled Python artifacts (__pycache__/*.pyc); remove them before scaffold validation" >&2
  find "$TEMPLATE_DIR" -type f \( -name '*.pyc' -o -path '*/__pycache__/*' \) -print >&2
  exit 1
fi

rm -rf "$SMOKE_ROOT"
mkdir -p "$SMOKE_ROOT"

run_case() {
  local name="$1"
  local enable_bff="$2"
  local enable_ci="$3"
  local out_dir="$SMOKE_ROOT/$name"

  echo "==> generating $name (bff=$enable_bff code_interpreter=$enable_ci)"
  copier copy --force --trust "$TEMPLATE_DIR" "$out_dir" \
    --data agent_name="${name}-core-a1b2" \
    --data app_id="${name}" \
    --data description="Smoke test scaffold ${name}" \
    --data region="eu-central-1" \
    --data environment="dev" \
    --data enable_guardrails=true \
    --data enable_code_interpreter="${enable_ci}" \
    --data enable_knowledge_base=false \
    --data enable_bff="${enable_bff}" \
    --data python_version="3.12"

  # Keep the inner loop fast and deterministic: validate the scaffold against the
  # local checkout modules instead of fetching this repo from GitHub.
  local tf_main="$out_dir/terraform/main.tf"
  for mod in foundation tools runtime governance bff; do
    sed -i "s|source = \"github.com/j3brns/tf-harness-acore//terraform/modules/agentcore-${mod}?ref=main\"|source = \"${REPO_ROOT}/terraform/modules/agentcore-${mod}\"|g" "$tf_main"
  done

  echo "==> validating generated Terraform for $name"
  if [[ "$SMOKE_MODE" == "full" ]]; then
    GIT_TERMINAL_PROMPT=0 terraform -chdir="$out_dir/terraform" init -backend=false -input=false >/dev/null
    terraform -chdir="$out_dir/terraform" validate >/dev/null
  else
    # Fast mode is a smoke test, not a style gate: parse the rendered HCL
    # without mutating files or requiring provider/plugin initialization.
    terraform -chdir="$out_dir/terraform" fmt -write=false >/dev/null
  fi

  echo "==> validating rendered files for $name"
  python3 - <<PY
from pathlib import Path
source = Path(r"$out_dir/agent-code/runtime.py").read_text(encoding="utf-8")
compile(source, r"$out_dir/agent-code/runtime.py", "exec")
PY
  if rg -n '\{\{[^}]+\}\}' "$out_dir" >/dev/null 2>&1; then
    echo "FAIL: unresolved template placeholders remain in $out_dir"
    rg -n '\{\{[^}]+\}\}' "$out_dir" || true
    exit 1
  fi

  if find "$out_dir" -type f \( -name '*.pyc' -o -path '*/__pycache__/*' \) | grep -q .; then
    echo "FAIL: generated scaffold contains compiled Python artifacts in $out_dir"
    find "$out_dir" -type f \( -name '*.pyc' -o -path '*/__pycache__/*' \) -print || true
    exit 1
  fi

  # Environment vocabulary and Python compatibility guardrails.
  grep -Fq 'default: "dev"' "$TEMPLATE_DIR/copier.yml"
  grep -Fq '    - "test"' "$TEMPLATE_DIR/copier.yml"
  if grep -Fq '    - "staging"' "$TEMPLATE_DIR/copier.yml"; then
    echo "FAIL: Copier template still exposes 'staging'; repo standard is dev/test/prod"
    exit 1
  fi
  grep -Fq '"3.12"' "$TEMPLATE_DIR/copier.yml"
}

run_case "smoke-runtime" "false" "false"
run_case "smoke-bff" "true" "true"

echo "Template scaffold smoke tests (${SMOKE_MODE}): PASS"

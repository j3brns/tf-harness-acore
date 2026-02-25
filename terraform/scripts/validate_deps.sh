#!/bin/bash
# Dependency Compatibility Validation
# Tests that recommended Strands / AgentCore SDK combinations resolve without
# conflicts. Scope: install/resolve only — not functional behavior correctness.
#
# Usage:
#   bash terraform/scripts/validate_deps.sh
#   make validate-deps
#
# Combinations validated (Python 3.12):
#   strands-core        — strands-agents + bedrock-agentcore (base combo)
#   strands-otel        — strands-agents[otel] + bedrock-agentcore (OTEL extras)
#   strands-deepresearch — strands-deep-agents + strands-agents-tools + bedrock-agentcore
#
# Exit codes: 0 = all combos OK, 1 = one or more combos failed

set -euo pipefail

# ---------------------------------------------------------------------------
# Python executable — prefer python3.12; fall back to python3 if not found
# ---------------------------------------------------------------------------
PYTHON="${PYTHON:-python3.12}"
if ! command -v "$PYTHON" &>/dev/null; then
    PYTHON="python3"
fi
if ! command -v "$PYTHON" &>/dev/null; then
    echo "ERROR: No Python interpreter found (tried python3.12, python3)."
    exit 1
fi

PYTHON_VERSION=$("$PYTHON" --version 2>&1)

# ---------------------------------------------------------------------------
# Pre-flight: verify venv / ensurepip are available
# ---------------------------------------------------------------------------
if ! "$PYTHON" -c "import ensurepip" 2>/dev/null; then
    echo "ERROR: ensurepip is not available for $PYTHON."
    echo "       On Debian/Ubuntu: sudo apt install python3.12-venv"
    echo "       On other systems: ensure the venv module is installed for your Python 3.12."
    exit 1
fi

# ---------------------------------------------------------------------------
# Combination matrix
# Format: "name|space-separated pip install specifiers"
# Versions are kept in sync with the floor constraints in examples/*/agent-code/pyproject.toml
# ---------------------------------------------------------------------------
COMBOS=(
    "strands-core|bedrock-agentcore>=1.0.7 strands-agents>=1.18.0"
    "strands-otel|bedrock-agentcore>=1.0.7 strands-agents[otel]>=1.18.0"
    "strands-deepresearch|bedrock-agentcore>=1.0.7 strands-agents>=1.18.0 strands-agents-tools>=0.2.16 strands-deep-agents>=0.1.1"
)

PASS=0
FAIL=0
FAILED_NAMES=()

# ---------------------------------------------------------------------------
# validate_combo <name> <packages>
# Returns 0 on success, 1 on conflict or install failure.
# ---------------------------------------------------------------------------
validate_combo() {
    local name="$1"
    local packages="$2"
    local tmpdir
    tmpdir=$(mktemp -d)

    echo ""
    echo "--- Validating: $name ---"
    echo "  Packages : $packages"

    # Create isolated virtual environment
    if ! "$PYTHON" -m venv "$tmpdir/venv" 2>&1; then
        echo "  ERROR: Failed to create virtual environment"
        rm -rf "$tmpdir"
        return 1
    fi

    local pip="$tmpdir/venv/bin/pip"

    # Upgrade pip quietly to get reliable resolver output
    "$pip" install --quiet --upgrade pip 2>&1

    # Install the combination; capture output for diagnostics
    local install_out
    local install_status
    set +e
    # shellcheck disable=SC2086  # word splitting intentional for $packages
    install_out=$("$pip" install $packages 2>&1)
    install_status=$?
    set -e

    if [ "$install_status" -ne 0 ]; then
        echo "  FAIL: pip install exited with status $install_status"
        echo ""
        echo "  --- pip install output (conflict / resolution details) ---"
        echo "$install_out"
        echo "  --- end pip install output ---"
        rm -rf "$tmpdir"
        return 1
    fi

    # Run pip check to detect transitive dependency inconsistencies
    local check_out
    local check_status
    set +e
    check_out=$("$pip" check 2>&1)
    check_status=$?
    set -e

    if [ "$check_status" -ne 0 ]; then
        echo "  FAIL: pip check reported dependency inconsistencies"
        echo ""
        echo "  --- pip check output ---"
        echo "$check_out"
        echo "  --- end pip check output ---"
        echo ""
        echo "  Installed SDK packages (for triage):"
        "$pip" list --format=columns 2>&1 \
            | grep -Ei "strands|bedrock|agentcore|opentelemetry" || true
        rm -rf "$tmpdir"
        return 1
    fi

    # Success — show installed SDK/OTEL versions for audit trail
    echo "  PASS: Dependencies resolve without conflicts"
    echo "  Installed SDK packages:"
    "$pip" list --format=columns 2>&1 \
        | grep -Ei "strands|bedrock|agentcore|opentelemetry" || true

    rm -rf "$tmpdir"
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "=========================================="
echo "Dependency Compatibility Validation"
echo "  Python   : $PYTHON_VERSION"
echo "  Combos   : ${#COMBOS[@]}"
echo "=========================================="

for combo in "${COMBOS[@]}"; do
    name="${combo%%|*}"
    packages="${combo##*|}"

    if validate_combo "$name" "$packages"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name")
    fi
done

echo ""
echo "=========================================="
echo "Dependency Validation Summary"
echo "  Passed : $PASS"
echo "  Failed : $FAIL"
if [ "${#FAILED_NAMES[@]}" -gt 0 ]; then
    echo "  Failing combinations:"
    for n in "${FAILED_NAMES[@]}"; do
        echo "    - $n"
    done
fi
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "FAIL: One or more dependency combinations have conflicts."
    echo "      See per-combo output above for package/version details."
    exit 1
fi

echo ""
echo "PASS: All dependency combinations resolve successfully."

#!/bin/bash
# Run Python tests for DeepResearch agent
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh unit         # Run unit tests only
#   ./run_tests.sh integration  # Run integration tests only
#   ./run_tests.sh coverage     # Run with coverage report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$AGENT_DIR"

# Install dependencies if needed
if ! python -c "import pytest" 2>/dev/null; then
    echo "Installing test dependencies..."
    pip install -e ".[dev]"
fi

TEST_TYPE="${1:-all}"

case "$TEST_TYPE" in
    unit)
        echo "Running unit tests..."
        python -m pytest tests/unit -v --tb=short
        ;;
    integration)
        echo "Running integration tests..."
        python -m pytest tests/integration -v --tb=short
        ;;
    coverage)
        echo "Running tests with coverage..."
        python -m pytest tests/ -v --tb=short \
            --cov=deepresearch \
            --cov-report=term-missing \
            --cov-report=html:coverage_html \
            --cov-report=xml:coverage.xml
        echo ""
        echo "Coverage report generated: coverage_html/index.html"
        ;;
    all|*)
        echo "Running all tests..."
        python -m pytest tests/ -v --tb=short
        ;;
esac

echo ""
echo "Tests completed successfully!"

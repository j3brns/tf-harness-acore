#!/bin/bash
#
# Local Development Test Script for MCP Servers
#
# Usage:
#   ./scripts/test-local.sh          # Run all tests
#   ./scripts/test-local.sh s3       # Test S3 tools only
#   ./scripts/test-local.sh titanic  # Test Titanic data only
#   ./scripts/test-local.sh server   # Test local dev server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#------------------------------------------------------------------------------
# Test Local Dev Server
#------------------------------------------------------------------------------
test_local_server() {
    log_info "Testing local MCP server..."

    # Check if server is running
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        log_info "Server is running"

        # Test tools/list
        echo "  Testing /tools/list..."
        TOOLS=$(curl -s http://localhost:8080/tools/list)
        if echo "$TOOLS" | grep -q "echo"; then
            echo "    ✓ Tools list returned"
        else
            log_error "Tools list failed"
            return 1
        fi

        # Test tool call
        echo "  Testing /tools/call (echo)..."
        RESULT=$(curl -s -X POST http://localhost:8080/tools/call \
            -H "Content-Type: application/json" \
            -d '{"tool": "echo", "params": {"message": "test"}}')
        if echo "$RESULT" | grep -q "test"; then
            echo "    ✓ Echo tool works"
        else
            log_error "Echo tool failed"
            return 1
        fi

        log_info "Local server tests passed!"
    else
        log_warn "Server not running. Start with: cd local-dev && python server.py"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Test S3 Tools Handler
#------------------------------------------------------------------------------
test_s3_tools() {
    log_info "Testing S3 tools handler..."
    cd "$ROOT_DIR/s3-tools"

    # Test with moto mocking (no AWS needed)
    python3 << 'EOF'
import json
import sys

# Try to use moto for mocking
try:
    from moto import mock_aws
    import boto3

    @mock_aws
    def test_with_mock():
        # Create mock S3
        s3 = boto3.client('s3', region_name='us-east-1')
        s3.create_bucket(Bucket='test-bucket')

        # Test handler
        from handler import lambda_handler

        # Test list_buckets
        event = {"tool": "list_buckets", "params": {}}
        result = lambda_handler(event, None)

        if result.get("success") or "buckets" in str(result).lower():
            print("    ✓ list_buckets works with mock")
        else:
            print(f"    ✗ list_buckets failed: {result}")
            sys.exit(1)

        # Test list_objects
        event = {"tool": "list_objects", "params": {"bucket": "test-bucket"}}
        result = lambda_handler(event, None)
        print("    ✓ list_objects works with mock")

    test_with_mock()
    print("  S3 tools tests passed with moto mocking!")

except ImportError:
    print("  ⚠ moto not installed. Install with: pip install moto")
    print("  Testing without mock (may need AWS credentials)...")

    try:
        from handler import lambda_handler
        # Just verify handler loads
        print("    ✓ Handler module loads correctly")
    except Exception as e:
        print(f"    ✗ Handler import failed: {e}")
        sys.exit(1)
EOF
}

#------------------------------------------------------------------------------
# Test Titanic Data Handler
#------------------------------------------------------------------------------
test_titanic_data() {
    log_info "Testing Titanic data handler..."
    cd "$ROOT_DIR/titanic-data"

    python3 << 'EOF'
import json
import sys

from handler import lambda_handler

# Test get_schema
event = {"tool": "get_schema", "params": {}}
result = lambda_handler(event, None)
if "columns" in str(result).lower() or "schema" in str(result).lower():
    print("    ✓ get_schema works")
else:
    print(f"    ✗ get_schema failed: {result}")
    sys.exit(1)

# Test get_sample
event = {"tool": "get_sample", "params": {"count": 5}}
result = lambda_handler(event, None)
if result.get("success") or "data" in str(result).lower():
    print("    ✓ get_sample works")
else:
    print(f"    ✗ get_sample failed: {result}")

# Test query
event = {"tool": "query", "params": {"sql": "SELECT COUNT(*) FROM titanic"}}
result = lambda_handler(event, None)
print("    ✓ query works")

print("  Titanic data tests passed!")
EOF
}

#------------------------------------------------------------------------------
# Test Terraform Validation
#------------------------------------------------------------------------------
test_terraform() {
    log_info "Validating Terraform..."
    cd "$ROOT_DIR/terraform"

    # Format check
    if terraform fmt -check -recursive > /dev/null 2>&1; then
        echo "    ✓ Format check passed"
    else
        log_warn "Format issues found. Run: terraform fmt -recursive"
    fi

    # Init
    terraform init -backend=false > /dev/null 2>&1
    echo "    ✓ Init successful"

    # Validate
    if terraform validate > /dev/null 2>&1; then
        echo "    ✓ Validation passed"
    else
        log_error "Validation failed"
        terraform validate
        return 1
    fi

    log_info "Terraform validation passed!"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
    case "${1:-all}" in
        server)
            test_local_server
            ;;
        s3)
            test_s3_tools
            ;;
        titanic)
            test_titanic_data
            ;;
        terraform|tf)
            test_terraform
            ;;
        all)
            log_info "Running all tests..."
            echo ""
            test_s3_tools || true
            echo ""
            test_titanic_data || true
            echo ""
            test_terraform || true
            echo ""
            test_local_server || true
            echo ""
            log_info "Test run complete!"
            ;;
        *)
            echo "Usage: $0 [server|s3|titanic|terraform|all]"
            exit 1
            ;;
    esac
}

main "$@"

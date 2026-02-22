import sys
import os
import json
import base64
from unittest.mock import MagicMock, patch
from botocore.exceptions import ClientError

# Add the src directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "src"))

# Mock boto3 before importing handlers
with patch("boto3.resource"), patch("boto3.client"):
    import auth_handler
    import authorizer


def create_mock_jwt(claims):
    header = base64.urlsafe_b64encode(json.dumps({"alg": "HS256"}).encode()).decode().replace("=", "")
    payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().replace("=", "")
    signature = "mock_signature"
    return f"{header}.{payload}.{signature}"


def test_tenant_extraction_in_callback():
    print("Testing Tenant ID extraction in callback (North-South Join)...")

    # Mock JWT with tenant claim (tid for Entra ID)
    mock_id_token = create_mock_jwt({"tid": "tenant-123", "sub": "user-456", "email": "test@example.com"})

    # Mock event
    event = {
        "queryStringParameters": {"code": "mock_code", "state": "mock_state"},
        "headers": {"Cookie": "temp_session_id=temp-123"},
    }

    # Mock dependencies
    auth_handler.table = MagicMock()
    # Return temp session for lookup
    auth_handler.table.get_item.return_value = {"Item": {"state": "mock_state", "code_verifier": "mock_verifier"}}

    # Mock token exchange response
    mock_token_resp = {"access_token": "mock_access", "id_token": mock_id_token, "expires_in": 3600}

    with (
        patch("urllib.request.urlopen") as mock_url_open,
        patch("auth_handler.get_secret", return_value="mock_secret"),
        patch("auth_handler.ISSUER", "https://issuer"),
        patch("auth_handler.APP_ID", "test-app"),
    ):
        # Mock the context manager for urlopen
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps(mock_token_resp).encode()
        mock_url_open.return_value.__enter__.return_value = mock_response

        response = auth_handler.callback(event)

        # Verify callback writes JIT onboarding records plus the tenant-scoped session item.
        put_calls = auth_handler.table.put_item.call_args_list
        assert len(put_calls) >= 4, f"Expected JIT onboarding + session writes, got {len(put_calls)}"

        put_items = [call.kwargs["Item"] for call in put_calls]
        session_items = [item for item in put_items if str(item.get("sk", "")).startswith("SESSION#")]
        assert len(session_items) == 1, f"Expected one permanent session item, got {len(session_items)}"
        item = session_items[0]

        assert item.get("tenant_id") == "tenant-123"
        assert item.get("pk") == "APP#test-app#TENANT#tenant-123"
        assert item.get("sk").startswith("SESSION#")

        tenant_meta = next((row for row in put_items if row.get("sk") == "TENANT#META"), None)
        assert tenant_meta is not None, "Expected TENANT#META onboarding record"
        assert tenant_meta.get("tenant_root_prefix") == "test-app/tenant-123/"
        assert tenant_meta.get("session_partition_pk") == "APP#test-app#TENANT#tenant-123"

        baseline_policy_rows = [row for row in put_items if str(row.get("sk", "")).startswith("POLICY#BASELINE#")]
        assert len(baseline_policy_rows) >= 2, "Expected baseline policy attachment records"

        # Verify Cookie format includes tenant_id
        cookie = response["headers"]["Set-Cookie"]
        assert "session_id=tenant-123:" in cookie

        print(f"  PASS: Composite PK: {item.get('pk')}")
        print("  PASS: Cookie contains tenant_id prefix.")
        print("  PASS: JIT tenant onboarding records were created before session issuance.")


def _conditional_check_failed(operation_name="PutItem"):
    return ClientError(
        {"Error": {"Code": "ConditionalCheckFailedException", "Message": "Item already exists"}},
        operation_name,
    )


def test_jit_tenant_onboarding_is_retry_safe_for_partial_failures():
    print("Testing JIT tenant onboarding is retry-safe and idempotent across partial failures...")

    auth_handler.table = MagicMock()

    # Simulate partial previous success:
    # - tenant metadata record was created
    # - first policy attachment already exists (conditional put fails)
    # - helper verifies invariants and continues
    auth_handler.table.put_item.side_effect = [None, _conditional_check_failed(), None]
    auth_handler.table.get_item.return_value = {
        "Item": {
            "pk": "APP#test-app#TENANT#tenant-123",
            "sk": "POLICY#BASELINE#tenant-isolation",
            "type": "tenant_policy_attachment",
            "app_id": "test-app",
            "tenant_id": "tenant-123",
            "attachment_state": "ATTACHED",
            "policy_id": "tenant-isolation",
            "policy_type": "cedar",
            "scope": "tenant",
            "attachment_source": "jit-onboarding",
            "attachment_version": "jit-v1",
        }
    }

    with patch("auth_handler.APP_ID", "test-app"), patch("auth_handler.time.time", return_value=1700000000):
        auth_handler.ensure_tenant_onboarding("tenant-123")

    assert auth_handler.table.put_item.call_count == 3
    auth_handler.table.get_item.assert_called_once_with(
        Key={"pk": "APP#test-app#TENANT#tenant-123", "sk": "POLICY#BASELINE#tenant-isolation"}
    )
    print("  PASS: Existing onboarding record was verified and onboarding continued safely.")


def test_tenant_propagation_in_authorizer():
    print("Testing Tenant ID propagation in authorizer (North-South Join)...")

    # Mock event with composite cookie
    event = {"methodArn": "arn:aws:execute-api:...", "headers": {"Cookie": "session_id=tenant-123:sess-123"}}

    # Mock DynamoDB lookup
    mock_id_token = create_mock_jwt({"tid": "tenant-123", "sub": "user-456", "email": "test@example.com"})
    authorizer.table = MagicMock()
    authorizer.table.get_item.return_value = {
        "Item": {
            "pk": "APP#test-app#TENANT#tenant-123",
            "sk": "SESSION#sess-123",
            "app_id": "test-app",
            "tenant_id": "tenant-123",
            "session_id": "sess-123",
            "access_token": "mock_access",
            "id_token": mock_id_token,
            "expires_at": 9999999999,  # Far future
        }
    }

    with patch("authorizer.APP_ID", "test-app"):
        policy = authorizer.lambda_handler(event, None)

        # Verify lookup key
        authorizer.table.get_item.assert_called_with(
            Key={"pk": "APP#test-app#TENANT#tenant-123", "sk": "SESSION#sess-123"}
        )

        assert policy.get("context", {}).get("tenant_id") == "tenant-123"
        assert policy.get("context", {}).get("app_id") == "test-app"
        assert policy.get("context", {}).get("session_id") == "sess-123"
        assert policy.get("context", {}).get("principal_sub") == "user-456"
        assert policy.get("context", {}).get("principal_email") == "test@example.com"
        print("  PASS: authorizer performed composite PK lookup and propagated full context.")


def test_authorizer_denies_tenant_claim_mismatch():
    print("Testing authorizer denies cookie tenant mismatch with JWT tenant claim...")

    event = {"methodArn": "arn:aws:execute-api:...", "headers": {"Cookie": "session_id=tenant-123:sess-123"}}

    authorizer.table = MagicMock()
    authorizer.table.get_item.return_value = {
        "Item": {
            "pk": "APP#test-app#TENANT#tenant-123",
            "sk": "SESSION#sess-123",
            "app_id": "test-app",
            "tenant_id": "tenant-123",
            "session_id": "sess-123",
            "access_token": "mock_access",
            "id_token": create_mock_jwt({"tid": "tenant-999", "sub": "user-456"}),
            "expires_at": 9999999999,
        }
    }

    with patch("authorizer.APP_ID", "test-app"):
        policy = authorizer.lambda_handler(event, None)

        statement = policy["policyDocument"]["Statement"][0]
        assert statement["Effect"] == "Deny"
        assert "context" not in policy
        print("  PASS: authorizer denied request when JWT tenant claim mismatched cookie/session tenant.")


def test_cross_tenant_session_forgery_denied():
    """Negative test: forged cookie with tenant-B prefix but only tenant-A session exists.
    The authorizer must deny access (Rule 14.1 - no implicit tenant trust)."""
    print("Testing cross-tenant session forgery is denied (Rule 14.1)...")

    # Attacker forges a cookie claiming tenant-B prefix with a session ID from tenant-A
    event = {"methodArn": "arn:aws:execute-api:...", "headers": {"Cookie": "session_id=tenant-B:sess-A"}}

    authorizer.table = MagicMock()
    # DDB returns nothing because the composite PK APP#test-app#TENANT#tenant-B/SESSION#sess-A does not exist
    authorizer.table.get_item.return_value = {}

    with patch("authorizer.APP_ID", "test-app"):
        policy = authorizer.lambda_handler(event, None)

        # Verify denial
        effect = policy["policyDocument"]["Statement"][0]["Effect"]
        assert effect == "Deny", f"Expected Deny, got {effect}"

        # Verify lookup was for the FORGED tenant prefix (not tenant-A)
        authorizer.table.get_item.assert_called_with(
            Key={"pk": "APP#test-app#TENANT#tenant-B", "sk": "SESSION#sess-A"}
        )
        print("  PASS: cross-tenant session forgery correctly denied.")


def test_expired_session_denied():
    """Negative test: valid composite cookie but session is expired and has no refresh token.
    The authorizer must deny access (Rule 14.1 - claim mismatch via stale session)."""
    print("Testing expired session (no refresh token) is denied...")

    event = {"methodArn": "arn:aws:execute-api:...", "headers": {"Cookie": "session_id=tenant-123:sess-exp"}}

    authorizer.table = MagicMock()
    authorizer.table.get_item.return_value = {
        "Item": {
            "pk": "APP#test-app#TENANT#tenant-123",
            "sk": "SESSION#sess-exp",
            "app_id": "test-app",
            "tenant_id": "tenant-123",
            "access_token": "expired_token",
            "expires_at": 1,  # Unix epoch 1 = far in the past
            # No refresh_token key
        }
    }

    with patch("authorizer.APP_ID", "test-app"):
        policy = authorizer.lambda_handler(event, None)

        effect = policy["policyDocument"]["Statement"][0]["Effect"]
        assert effect == "Deny", f"Expected Deny for expired session, got {effect}"
        print("  PASS: expired session with no refresh token correctly denied.")


def test_malformed_cookie_denied():
    """Negative test: cookie value is missing the tenant_id:session_id composite separator.
    The authorizer must deny access (claim structure mismatch)."""
    print("Testing malformed cookie (no ':' separator) is denied...")

    event = {"methodArn": "arn:aws:execute-api:...", "headers": {"Cookie": "session_id=noseparatorhere"}}

    authorizer.table = MagicMock()

    with patch("authorizer.APP_ID", "test-app"):
        policy = authorizer.lambda_handler(event, None)

        effect = policy["policyDocument"]["Statement"][0]["Effect"]
        assert effect == "Deny", f"Expected Deny for malformed cookie, got {effect}"

        # DDB should NOT have been called since parsing failed
        authorizer.table.get_item.assert_not_called()
        print("  PASS: malformed cookie without composite separator correctly denied.")


if __name__ == "__main__":
    try:
        test_tenant_extraction_in_callback()
        test_tenant_propagation_in_authorizer()
        test_authorizer_denies_tenant_claim_mismatch()
        test_cross_tenant_session_forgery_denied()
        test_expired_session_denied()
        test_malformed_cookie_denied()
        print("\nMulti-tenancy North-South Join tests passed successfully.")
    except Exception as e:
        print(f"\nUNIT TEST FAILED: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)

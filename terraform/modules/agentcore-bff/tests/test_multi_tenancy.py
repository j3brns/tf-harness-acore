import sys
import os
import json
import base64
from unittest.mock import MagicMock, patch

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

        # Verify DDB storage includes tenant_id and composite PK/SK
        auth_handler.table.put_item.assert_called_once()
        item = auth_handler.table.put_item.call_args[1]["Item"]

        assert item.get("tenant_id") == "tenant-123"
        assert item.get("pk") == "APP#test-app#TENANT#tenant-123"
        assert item.get("sk").startswith("SESSION#")

        # Verify Cookie format includes tenant_id
        cookie = response["headers"]["Set-Cookie"]
        assert "session_id=tenant-123:" in cookie

        print(f"  PASS: Composite PK: {item.get('pk')}")
        print("  PASS: Cookie contains tenant_id prefix.")


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


if __name__ == "__main__":
    try:
        test_tenant_extraction_in_callback()
        test_tenant_propagation_in_authorizer()
        test_authorizer_denies_tenant_claim_mismatch()
        print("\nMulti-tenancy North-South Join tests passed successfully.")
    except Exception as e:
        print(f"\nUNIT TEST FAILED: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)

import sys
import os
from unittest.mock import MagicMock, patch

# Add the src directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "src"))

# Mock boto3 before importing auth_handler
with patch("boto3.resource"), patch("boto3.client"):
    import auth_handler


def test_pkce_generation():
    print("Testing PKCE Pair Generation...")
    verifier, challenge = auth_handler.generate_pkce_pair()

    assert len(verifier) >= 43  # Min length for 32 bytes entropy
    assert "=" not in challenge
    assert "+" not in challenge
    assert "/" not in challenge
    print(f"  PASS: Verifier and Challenge look valid. Challenge: {challenge}")


def test_login_flow():
    print("Testing Login Flow logic...")
    event = {"path": "/auth/login"}

    # Mock DynamoDB table
    auth_handler.table = MagicMock()

    with patch("auth_handler.ISSUER", "https://login.microsoftonline.com/tenant"):
        response = auth_handler.login(event)

        assert response["statusCode"] == 302
        location = response["headers"]["Location"]
        assert "code_challenge=" in location
        assert "code_challenge_method=S256" in location

        # Verify DDB storage
        auth_handler.table.put_item.assert_called_once()
        item = auth_handler.table.put_item.call_args[1]["Item"]
        assert item["session_id"].startswith("temp_")
        assert "code_verifier" in item

        # Verify Cookie
        cookies = response["multiValueHeaders"]["Set-Cookie"]
        assert any("temp_session_id=" in c for c in cookies)
        print("  PASS: Login redirect and state storage verified.")


if __name__ == "__main__":
    try:
        test_pkce_generation()
        test_login_flow()
        print("\nUnit tests passed successfully.")
    except Exception as e:
        print(f"\nUNIT TEST FAILED: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)

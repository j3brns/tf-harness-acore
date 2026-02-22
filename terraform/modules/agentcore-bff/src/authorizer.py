import os
import boto3
import time
import json
import base64
import urllib.parse
import urllib.request
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

DDB_TABLE = os.environ.get("SESSION_TABLE")
APP_ID = os.environ.get("APP_ID")
CLIENT_ID = os.environ.get("CLIENT_ID")
CLIENT_SECRET_ARN = os.environ.get("CLIENT_SECRET_ARN")
ISSUER = os.environ.get("ISSUER")
TOKEN_ENDPOINT = os.environ.get("TOKEN_ENDPOINT")

ddb = boto3.resource("dynamodb")
secrets_client = boto3.client("secretsmanager")
table = ddb.Table(DDB_TABLE)


def decode_jwt_claims(token):
    if not token:
        return {}
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return {}
        payload = parts[1]
        missing_padding = len(payload) % 4
        if missing_padding:
            payload += "=" * (4 - missing_padding)
        decoded = base64.urlsafe_b64decode(payload).decode("utf-8")
        return json.loads(decoded)
    except Exception as e:
        logger.error(f"Error decoding JWT in authorizer: {e}")
        return {}


def extract_tenant_claim(item):
    # Prefer id_token (OIDC identity claims), then fall back to access_token if it is a JWT.
    for field in ("id_token", "access_token"):
        claims = decode_jwt_claims(item.get(field))
        tenant_claim = claims.get("tid") or claims.get("tenant_id")
        if tenant_claim:
            return str(tenant_claim), claims
    return None, {}


def get_secret(arn):
    if not arn:
        return None
    try:
        resp = secrets_client.get_secret_value(SecretId=arn)
        return resp["SecretString"]
    except Exception as e:
        logger.error(f"Error fetching secret: {e}")
        return None


def get_token_url():
    """Get the token endpoint URL using discovery or fallback to Entra ID."""
    if TOKEN_ENDPOINT:
        return TOKEN_ENDPOINT
    # Fallback to Entra ID format if discovery is not available
    return f"{ISSUER.rstrip('/')}/oauth2/v2.0/token"


def refresh_session(tenant_id, session_id, refresh_token):
    """Attempt to refresh the OIDC session using the refresh token."""
    logger.info(f"Refreshing session for tenant {tenant_id}, session {session_id}")

    secret = get_secret(CLIENT_SECRET_ARN)
    exchange_data = {
        "client_id": CLIENT_ID,
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    }
    if secret:
        exchange_data["client_secret"] = secret

    data = urllib.parse.urlencode(exchange_data).encode()
    token_url = get_token_url()
    req = urllib.request.Request(token_url, data=data, method="POST")

    try:
        with urllib.request.urlopen(req) as resp:
            token_resp = json.loads(resp.read().decode())

        new_access_token = token_resp["access_token"]
        new_refresh_token = token_resp.get("refresh_token", refresh_token)
        expires_in = token_resp.get("expires_in", 3600)
        new_expires_at = int(time.time()) + expires_in

        # Update DynamoDB
        table.update_item(
            Key={"pk": f"APP#{APP_ID}#TENANT#{tenant_id}", "sk": f"SESSION#{session_id}"},
            UpdateExpression="SET access_token = :at, refresh_token = :rt, expires_at = :ex",
            ExpressionAttributeValues={":at": new_access_token, ":rt": new_refresh_token, ":ex": new_expires_at},
        )

        return new_access_token, new_expires_at
    except Exception as e:
        logger.error(f"Session refresh failed: {e}")
        return None, None


def generate_policy(principal_id, effect, resource, context=None):
    policy = {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [{"Action": "execute-api:Invoke", "Effect": effect, "Resource": resource}],
        },
    }
    if context:
        policy["context"] = context
    return policy


def lambda_handler(event, context):
    headers = event.get("headers", {})
    # Case insensitive header lookup
    cookie_header = next((v for k, v in headers.items() if k.lower() == "cookie"), None)

    if not cookie_header:
        return generate_policy("user", "Deny", event["methodArn"])

    # Parse Cookie
    cookies = {c.split("=")[0].strip(): c.split("=")[1].strip() for c in cookie_header.split(";") if "=" in c}
    raw_session = cookies.get("session_id")

    if not raw_session:
        return generate_policy("user", "Deny", event["methodArn"])

    # Split tenant_id and session_id from composite cookie
    if ":" not in raw_session:
        return generate_policy("user", "Deny", event["methodArn"])

    tenant_id, session_id = raw_session.split(":", 1)

    # Lookup Session using North-South Join PK/SK
    resp = table.get_item(Key={"pk": f"APP#{APP_ID}#TENANT#{tenant_id}", "sk": f"SESSION#{session_id}"})
    item = resp.get("Item")

    if not item:
        logger.warning("Authorizer deny: session not found for app/tenant/session key")
        return generate_policy("user", "Deny", event["methodArn"])

    # Rule 14.1: Never trust cookie tenant/session without verifying the stored session record.
    stored_tenant_id = str(item.get("tenant_id", ""))
    stored_app_id = str(item.get("app_id", ""))
    stored_session_id = str(item.get("session_id", session_id))

    if stored_tenant_id and stored_tenant_id != tenant_id:
        logger.warning("Authorizer deny: cookie tenant_id mismatch with stored session tenant_id")
        return generate_policy("user", "Deny", event["methodArn"])
    if stored_app_id and stored_app_id != APP_ID:
        logger.warning("Authorizer deny: session app_id mismatch")
        return generate_policy("user", "Deny", event["methodArn"])
    if stored_session_id and stored_session_id != session_id:
        logger.warning("Authorizer deny: cookie session_id mismatch with stored session session_id")
        return generate_policy("user", "Deny", event["methodArn"])

    # Claim-scoped tenancy enforcement: tenant in session must match JWT tenant claim.
    claim_tenant_id, claims = extract_tenant_claim(item)
    if not claim_tenant_id:
        logger.warning("Authorizer deny: no tenant claim found in session tokens")
        return generate_policy("user", "Deny", event["methodArn"])
    if claim_tenant_id != tenant_id:
        logger.warning("Authorizer deny: tenant claim mismatch")
        return generate_policy("user", "Deny", event["methodArn"])

    access_token = item["access_token"]
    expires_at = item["expires_at"]
    refresh_token = item.get("refresh_token")

    # If expired or close to expiring (within 5 mins), try refresh
    if expires_at < (time.time() + 300) and refresh_token:
        new_token, new_expiry = refresh_session(tenant_id, session_id, refresh_token)
        if new_token:
            access_token = new_token
            expires_at = new_expiry
        elif expires_at < time.time():
            # Refresh failed and already expired
            return generate_policy("user", "Deny", event["methodArn"])
    elif expires_at < time.time():
        # Expired and no refresh token
        return generate_policy("user", "Deny", event["methodArn"])

    # Allow
    return generate_policy(
        principal_id=session_id,
        effect="Allow",
        resource=event["methodArn"],
        context={
            "access_token": access_token,
            "session_id": session_id,
            "tenant_id": tenant_id,
            "app_id": APP_ID,
            "principal_sub": str(claims.get("sub") or claims.get("oid") or ""),
            "principal_email": str(claims.get("email") or claims.get("upn") or ""),
        },
    )

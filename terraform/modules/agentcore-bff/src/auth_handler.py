import json
import os
import time
import uuid
import urllib.parse
import urllib.request
import hashlib
import base64
import secrets
import boto3
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

DDB_TABLE = os.environ.get("SESSION_TABLE")
APP_ID = os.environ.get("APP_ID")
CLIENT_ID = os.environ.get("CLIENT_ID")
CLIENT_SECRET_ARN = os.environ.get("CLIENT_SECRET_ARN")
REDIRECT_URI = os.environ.get("REDIRECT_URI")
ISSUER = os.environ.get("ISSUER")
AUTH_ENDPOINT = os.environ.get("AUTHORIZATION_ENDPOINT")
TOKEN_ENDPOINT = os.environ.get("TOKEN_ENDPOINT")

ddb = boto3.resource("dynamodb")
secrets_client = boto3.client("secretsmanager")
table = ddb.Table(DDB_TABLE)

JIT_ONBOARDING_VERSION = "jit-v1"
BASELINE_POLICY_ATTACHMENTS = (
    {
        "policy_id": "tenant-isolation",
        "policy_type": "cedar",
        "scope": "tenant",
    },
    {
        "policy_id": "session-partition-boundary",
        "policy_type": "session",
        "scope": "tenant",
    },
)


def get_auth_url(params):
    """Get the authorization URL using discovery or fallback to Entra ID."""
    if AUTH_ENDPOINT:
        return f"{AUTH_ENDPOINT}?{urllib.parse.urlencode(params)}"
    # Fallback to Entra ID format if discovery is not available
    return f"{ISSUER.rstrip('/')}/oauth2/v2.0/authorize?{urllib.parse.urlencode(params)}"


def get_token_url():
    """Get the token endpoint URL using discovery or fallback to Entra ID."""
    if TOKEN_ENDPOINT:
        return TOKEN_ENDPOINT
    # Fallback to Entra ID format if discovery is not available
    return f"{ISSUER.rstrip('/')}/oauth2/v2.0/token"


def get_secret(arn):
    if not arn:
        return None
    try:
        resp = secrets_client.get_secret_value(SecretId=arn)
        return resp["SecretString"]
    except Exception as e:
        logger.error(f"Error fetching secret: {e}")
        return None


def generate_pkce_pair():
    # https://tools.ietf.org/html/rfc7636#section-4.1
    verifier = secrets.token_urlsafe(32)
    challenge_hash = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(challenge_hash).decode("ascii").replace("=", "")
    return verifier, challenge


def decode_jwt_claims(token):
    try:
        # JWT format: header.payload.signature
        parts = token.split(".")
        if len(parts) != 3:
            return {}
        payload = parts[1]
        # Add padding if needed
        missing_padding = len(payload) % 4
        if missing_padding:
            payload += "=" * (4 - missing_padding)
        decoded = base64.urlsafe_b64decode(payload).decode("utf-8")
        return json.loads(decoded)
    except Exception as e:
        logger.error(f"Error decoding JWT: {e}")
        return {}


def tenant_pk(tenant_id):
    return f"APP#{APP_ID}#TENANT#{tenant_id}"


def put_item_if_absent(item, invariant_fields):
    """Create an item once; if it already exists, verify invariant fields match."""
    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(pk) AND attribute_not_exists(sk)")
        return "created"
    except ClientError as err:
        error_code = err.response.get("Error", {}).get("Code")
        if error_code != "ConditionalCheckFailedException":
            raise

        resp = table.get_item(Key={"pk": item["pk"], "sk": item["sk"]})
        existing = resp.get("Item")
        if not existing:
            raise RuntimeError(f"Existing item not readable after conditional failure for {item['pk']} / {item['sk']}")

        for field in invariant_fields:
            if existing.get(field) != item.get(field):
                raise RuntimeError(
                    f"JIT onboarding invariant mismatch for {item['pk']} / {item['sk']} field {field}: "
                    f"{existing.get(field)!r} != {item.get(field)!r}"
                )
        return "existing"


def ensure_tenant_onboarding(tenant_id):
    """JIT provision logical tenant records on first successful OIDC authentication."""
    pk = tenant_pk(tenant_id)
    now = int(time.time())
    tenant_root_prefix = f"{APP_ID}/{tenant_id}/"

    records = [
        (
            {
                "pk": pk,
                "sk": "TENANT#META",
                "type": "tenant",
                "app_id": APP_ID,
                "tenant_id": tenant_id,
                "onboarding_state": "READY",
                "onboarding_version": JIT_ONBOARDING_VERSION,
                "tenant_root_prefix": tenant_root_prefix,
                "session_partition_pk": pk,
                "created_at": now,
                "updated_at": now,
            },
            [
                "type",
                "app_id",
                "tenant_id",
                "onboarding_state",
                "onboarding_version",
                "tenant_root_prefix",
                "session_partition_pk",
            ],
        )
    ]

    for attachment in BASELINE_POLICY_ATTACHMENTS:
        records.append(
            (
                {
                    "pk": pk,
                    "sk": f"POLICY#BASELINE#{attachment['policy_id']}",
                    "type": "tenant_policy_attachment",
                    "app_id": APP_ID,
                    "tenant_id": tenant_id,
                    "attachment_state": "ATTACHED",
                    "policy_id": attachment["policy_id"],
                    "policy_type": attachment["policy_type"],
                    "scope": attachment["scope"],
                    "attachment_source": "jit-onboarding",
                    "attachment_version": JIT_ONBOARDING_VERSION,
                    "created_at": now,
                    "updated_at": now,
                },
                [
                    "type",
                    "app_id",
                    "tenant_id",
                    "attachment_state",
                    "policy_id",
                    "policy_type",
                    "scope",
                    "attachment_source",
                    "attachment_version",
                ],
            )
        )

    created = 0
    reused = 0
    for item, invariant_fields in records:
        result = put_item_if_absent(item, invariant_fields)
        if result == "created":
            created += 1
        else:
            reused += 1

    logger.info(
        "JIT tenant onboarding ensured for app_id=%s tenant_id=%s (created=%s reused=%s)",
        APP_ID,
        tenant_id,
        created,
        reused,
    )


def login(event):
    state = str(uuid.uuid4())
    nonce = str(uuid.uuid4())
    code_verifier, code_challenge = generate_pkce_pair()

    # Store state/nonce/verifier in DDB (TTL = 10 mins)
    temp_session_id = str(uuid.uuid4())
    expires_at = int(time.time()) + 600  # 10 minutes

    table.put_item(
        Item={
            "pk": f"APP#{APP_ID}#TEMP",
            "sk": f"SESSION#{temp_session_id}",
            "state": state,
            "nonce": nonce,
            "code_verifier": code_verifier,
            "expires_at": expires_at,
            "type": "temp",
            "app_id": APP_ID,
        }
    )

    params = {
        "client_id": CLIENT_ID,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "scope": "openid profile email",
        "state": state,
        "nonce": nonce,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }

    auth_url = get_auth_url(params)

    # Temporary cookie to link callback back to verifier
    cookie = f"temp_session_id={temp_session_id}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=600"

    return {
        "statusCode": 302,
        "headers": {"Location": auth_url, "Set-Cookie": cookie},
        "multiValueHeaders": {"Set-Cookie": [cookie]},
        "body": "",
    }


def callback(event):
    query_params = event.get("queryStringParameters", {})
    code = query_params.get("code")
    state = query_params.get("state")

    if not code or not state:
        return {"statusCode": 400, "body": "Missing code or state"}

    # Retrieve temp session from cookie
    headers = event.get("headers", {})
    cookie_header = next((v for k, v in headers.items() if k.lower() == "cookie"), None)
    temp_session_id = None
    if cookie_header:
        cookies = {c.split("=")[0].strip(): c.split("=")[1].strip() for c in cookie_header.split(";") if "=" in c}
        temp_session_id = cookies.get("temp_session_id")

    if not temp_session_id:
        return {"statusCode": 400, "body": "Missing temporary session cookie"}

    # Lookup Temp Session
    resp = table.get_item(Key={"pk": f"APP#{APP_ID}#TEMP", "sk": f"SESSION#{temp_session_id}"})
    temp_item = resp.get("Item")

    if not temp_item:
        return {"statusCode": 400, "body": "Session expired or invalid"}

    # Validate State
    if temp_item.get("state") != state:
        return {"statusCode": 400, "body": "Invalid state"}

    code_verifier = temp_item.get("code_verifier")

    # Exchange code for token
    secret = get_secret(CLIENT_SECRET_ARN)
    exchange_data = {
        "client_id": CLIENT_ID,
        "scope": "openid profile email",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "grant_type": "authorization_code",
        "code_verifier": code_verifier,
    }
    if secret:
        exchange_data["client_secret"] = secret

    data = urllib.parse.urlencode(exchange_data).encode()

    token_url = get_token_url()
    req = urllib.request.Request(token_url, data=data, method="POST")

    try:
        with urllib.request.urlopen(req) as resp:
            token_resp = json.loads(resp.read().decode())
    except Exception as e:
        logger.error(f"Token exchange failed: {e}")
        return {"statusCode": 500, "body": "Token exchange failed"}

    # Cleanup temp session
    table.delete_item(Key={"pk": f"APP#{APP_ID}#TEMP", "sk": f"SESSION#{temp_session_id}"})

    # Create Permanent Session
    session_id = str(uuid.uuid4())
    expires_in = token_resp.get("expires_in", 3600)
    expires_at = int(time.time()) + expires_in

    # Extract tenant_id from id_token (tid claim for Entra ID)
    id_token = token_resp.get("id_token")
    claims = decode_jwt_claims(id_token) if id_token else {}
    tenant_id = claims.get("tid", "unknown")

    try:
        ensure_tenant_onboarding(tenant_id)
    except Exception as e:
        logger.error(f"JIT tenant onboarding failed for tenant {tenant_id}: {e}")
        return {"statusCode": 500, "body": "Tenant onboarding failed"}

    table.put_item(
        Item={
            "pk": f"APP#{APP_ID}#TENANT#{tenant_id}",
            "sk": f"SESSION#{session_id}",
            "tenant_id": tenant_id,
            "app_id": APP_ID,
            "session_id": session_id,
            "access_token": token_resp["access_token"],
            "id_token": id_token,
            "refresh_token": token_resp.get("refresh_token"),
            "expires_at": expires_at,
            "type": "session",
        }
    )

    # Secure Cookie including tenant_id for PK construction
    cookie = f"session_id={tenant_id}:{session_id}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age={expires_in}"
    # Expire the temp cookie
    expire_temp = "temp_session_id=; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"

    return {
        "statusCode": 302,
        "headers": {"Location": "/", "Set-Cookie": cookie},
        "multiValueHeaders": {"Set-Cookie": [cookie, expire_temp]},
        "body": "",
    }


def lambda_handler(event, context):
    path = event.get("path", "")
    if path.endswith("/login"):
        return login(event)
    elif path.endswith("/callback"):
        return callback(event)
    else:
        return {"statusCode": 404, "body": "Not found"}

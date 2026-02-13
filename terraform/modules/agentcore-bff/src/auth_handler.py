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

DDB_TABLE = os.environ.get("SESSION_TABLE")
APP_ID = os.environ.get("APP_ID")
CLIENT_ID = os.environ.get("CLIENT_ID")
CLIENT_SECRET_ARN = os.environ.get("CLIENT_SECRET_ARN")
REDIRECT_URI = os.environ.get("REDIRECT_URI")
ISSUER = os.environ.get("ISSUER")

ddb = boto3.resource("dynamodb")
secrets_client = boto3.client("secretsmanager")
table = ddb.Table(DDB_TABLE)


def get_secret(arn):
    if not arn:
        return None
    try:
        resp = secrets_client.get_secret_value(SecretId=arn)
        return resp["SecretString"]
    except Exception as e:
        print(f"Error fetching secret: {e}")
        return None


def generate_pkce_pair():
    # https://tools.ietf.org/html/rfc7636#section-4.1
    verifier = secrets.token_urlsafe(32)
    challenge_hash = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(challenge_hash).decode("ascii").replace("=", "")
    return verifier, challenge


def login(event):
    state = str(uuid.uuid4())
    nonce = str(uuid.uuid4())
    code_verifier, code_challenge = generate_pkce_pair()

    # Store state/nonce/verifier in DDB (TTL = 10 mins)
    temp_session_id = str(uuid.uuid4())
    expires_at = int(time.time()) + 600  # 10 minutes

    table.put_item(
        Item={
            "app_id": APP_ID,
            "session_id": f"temp_{temp_session_id}",
            "state": state,
            "nonce": nonce,
            "code_verifier": code_verifier,
            "expires_at": expires_at,
            "type": "temp",
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

    auth_url = f"{ISSUER.rstrip('/')}/oauth2/v2.0/authorize?{urllib.parse.urlencode(params)}"

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
    resp = table.get_item(Key={"app_id": APP_ID, "session_id": f"temp_{temp_session_id}"})
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

    token_url = f"{ISSUER.rstrip('/')}/oauth2/v2.0/token"
    req = urllib.request.Request(token_url, data=data, method="POST")

    try:
        with urllib.request.urlopen(req) as resp:
            token_resp = json.loads(resp.read().decode())
    except Exception as e:
        print(f"Token exchange failed: {e}")
        return {"statusCode": 500, "body": "Token exchange failed"}

    # Cleanup temp session
    table.delete_item(Key={"app_id": APP_ID, "session_id": f"temp_{temp_session_id}"})

    # Create Permanent Session
    session_id = str(uuid.uuid4())
    expires_in = token_resp.get("expires_in", 3600)
    expires_at = int(time.time()) + expires_in

    table.put_item(
        Item={
            "app_id": APP_ID,
            "session_id": session_id,
            "access_token": token_resp["access_token"],
            "id_token": token_resp.get("id_token"),
            "refresh_token": token_resp.get("refresh_token"),
            "expires_at": expires_at,
            "type": "session",
        }
    )

    # Secure Cookie
    cookie = f"session_id={session_id}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age={expires_in}"
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

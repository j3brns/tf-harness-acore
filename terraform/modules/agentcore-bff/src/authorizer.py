import os
import boto3
import time

DDB_TABLE = os.environ.get("SESSION_TABLE")
APP_ID = os.environ.get("APP_ID")
ddb = boto3.resource("dynamodb")
table = ddb.Table(DDB_TABLE)


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
    session_id = cookies.get("session_id")

    if not session_id:
        return generate_policy("user", "Deny", event["methodArn"])

    # Lookup Session
    resp = table.get_item(Key={"app_id": APP_ID, "session_id": session_id})
    item = resp.get("Item")

    if not item or item["expires_at"] < time.time():
        return generate_policy("user", "Deny", event["methodArn"])

    # Allow
    return generate_policy(
        principal_id=session_id,
        effect="Allow",
        resource=event["methodArn"],
        context={"access_token": item["access_token"]},  # Injected for Proxy
    )

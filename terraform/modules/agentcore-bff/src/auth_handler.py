import json
import os
import time
import uuid
import urllib.parse
import urllib.request
import boto3

DDB_TABLE = os.environ.get('SESSION_TABLE')
CLIENT_ID = os.environ.get('CLIENT_ID')
CLIENT_SECRET_ARN = os.environ.get('CLIENT_SECRET_ARN')
REDIRECT_URI = os.environ.get('REDIRECT_URI')
ISSUER = os.environ.get('ISSUER')

ddb = boto3.resource('dynamodb')
secrets = boto3.client('secretsmanager')
table = ddb.Table(DDB_TABLE)

def get_secret(arn):
    if not arn: return None
    try:
        resp = secrets.get_secret_value(SecretId=arn)
        return resp['SecretString']
    except Exception as e:
        print(f"Error fetching secret: {e}")
        return None

def login(event):
    state = str(uuid.uuid4())
    nonce = str(uuid.uuid4())
    
    # Store state/nonce if strict OIDC
    
    params = {
        "client_id": CLIENT_ID,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "scope": "openid profile email",
        "state": state,
        "nonce": nonce
    }
    
    auth_url = f"{ISSUER}/oauth2/v2.0/authorize?{urllib.parse.urlencode(params)}"
    
    return {
        "statusCode": 302,
        "headers": {
            "Location": auth_url
        }
    }

def callback(event):
    code = event.get('queryStringParameters', {}).get('code')
    if not code:
        return {"statusCode": 400, "body": "Missing code"}

    # Exchange code for token
    secret = get_secret(CLIENT_SECRET_ARN)
    data = urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "scope": "openid profile email",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "grant_type": "authorization_code",
        "client_secret": secret
    }).encode()

    token_url = f"{ISSUER}/oauth2/v2.0/token"
    req = urllib.request.Request(token_url, data=data, method='POST')
    
    try:
        with urllib.request.urlopen(req) as resp:
            token_resp = json.loads(resp.read().decode())
    except Exception as e:
        print(f"Token exchange failed: {e}")
        return {"statusCode": 500, "body": "Token exchange failed"}

    # Create Session
    session_id = str(uuid.uuid4())
    expires_in = token_resp.get('expires_in', 3600)
    expires_at = int(time.time()) + expires_in

    table.put_item(Item={
        'session_id': session_id,
        'access_token': token_resp['access_token'],
        'id_token': token_resp.get('id_token'),
        'refresh_token': token_resp.get('refresh_token'),
        'expires_at': expires_at
    })

    # Secure Cookie
    cookie = f"session_id={session_id}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age={expires_in}"

    return {
        "statusCode": 302,
        "headers": {
            "Set-Cookie": cookie,
            "Location": "/" # Back to SPA
        }
    }

def lambda_handler(event, context):
    path = event.get('path', '')
    if path.endswith('/login'):
        return login(event)
    elif path.endswith('/callback'):
        return callback(event)
    else:
        return {"statusCode": 404, "body": "Not found"}

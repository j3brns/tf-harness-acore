#!/usr/bin/env python3
import boto3
import subprocess
import json
import uuid
import time
import sys
import os

def get_outputs():
    try:
        # Run from terraform root if possible, or assume typical layout
        cwd = os.getcwd()
        if 'terraform' not in cwd:
            tf_dir = os.path.join(cwd, 'terraform')
        else:
            tf_dir = cwd
            
        print(f"Reading Terraform outputs from {tf_dir}...")
        cmd = ["terraform", "output", "-json"]
        res = subprocess.check_output(cmd, cwd=tf_dir).decode()
        return json.loads(res)
    except Exception as e:
        print(f"Error reading outputs: {e}")
        sys.exit(1)

def main():
    outputs = get_outputs()
    
    # Check if BFF is enabled
    api_id = outputs.get('agentcore_bff_rest_api_id', {}).get('value')
    if not api_id:
        print("BFF module not enabled or not deployed. Skipping validation.")
        return

    auth_id = outputs['agentcore_bff_authorizer_id']['value']
    table_name = outputs['agentcore_bff_session_table_name']['value']
    region = boto3.session.Session().region_name or 'us-east-1' # Default fallback

    print(f"Validating API: {api_id}, Authorizer: {auth_id}, Table: {table_name}")

    # 1. Test Missing Cookie (Expect Deny)
    print("
[1/2] Testing Missing Cookie...")
    cmd = [
        "aws", "apigateway", "test-invoke-authorizer",
        "--rest-api-id", api_id,
        "--authorizer-id", auth_id,
        "--headers", "{}",
        "--region", region
    ]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        out = json.loads(res)
        policy = json.loads(out['policy'])
        effect = policy['policyDocument']['Statement'][0]['Effect']
        print(f"Result: {effect}")
        if effect != "Deny":
            print("FAIL: Expected Deny")
            sys.exit(1)
        else:
            print("PASS")
    except subprocess.CalledProcessError as e:
        print(f"AWS CLI Error: {e.output.decode()}")
        sys.exit(1)

    # 2. Test Valid Cookie (Expect Allow)
    print("
[2/2] Testing Valid Cookie (Mocking Session)...")
    ddb = boto3.resource('dynamodb', region_name=region)
    table = ddb.Table(table_name)
    
    session_id = str(uuid.uuid4())
    table.put_item(Item={
        'session_id': session_id,
        'access_token': 'mock_token_for_validation',
        'expires_at': int(time.time()) + 300
    })
    print(f"Inserted mock session: {session_id}")

    # Valid Cookie Header
    headers = {"Cookie": f"session_id={session_id}"}
    
    cmd = [
        "aws", "apigateway", "test-invoke-authorizer",
        "--rest-api-id", api_id,
        "--authorizer-id", auth_id,
        "--headers", json.dumps(headers),
        "--region", region
    ]
    
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        out = json.loads(res)
        policy = json.loads(out['policy'])
        effect = policy['policyDocument']['Statement'][0]['Effect']
        context_token = out['authorization'].get('access_token')
        
        print(f"Result: {effect}")
        print(f"Context Token: {context_token}")

        if effect != "Allow":
            print("FAIL: Expected Allow")
            sys.exit(1)
        if context_token != 'mock_token_for_validation':
            print("FAIL: Context propagation failed")
            sys.exit(1)
            
        print("PASS")
    except subprocess.CalledProcessError as e:
        print(f"AWS CLI Error: {e.output.decode()}")
        sys.exit(1)

    print("
BFF Validation Successful.")

if __name__ == "__main__":
    main()

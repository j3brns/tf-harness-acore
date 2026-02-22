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
        if "terraform" not in cwd:
            tf_dir = os.path.join(cwd, "terraform")
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
    api_id = outputs.get("agentcore_bff_rest_api_id", {}).get("value")
    if not api_id:
        print("BFF module not enabled or not deployed. Skipping validation.")
        return

    auth_id = outputs["agentcore_bff_authorizer_id"]["value"]
    table_name = outputs["agentcore_bff_session_table_name"]["value"]
    app_id = outputs.get("app_id", {}).get("value") or outputs["agent_name"]["value"]
    region = boto3.session.Session().region_name or "eu-west-2"

    print("Validating BFF Smoke Test [North-South Join Model]")
    print(f"API: {api_id}, Authorizer: {auth_id}, Table: {table_name}, AppID: {app_id}")

    # 1. Test Missing Cookie (Expect Deny)
    print("\n[1/2] Testing Missing Cookie (Expect Deny)...")
    cmd = [
        "aws",
        "apigateway",
        "test-invoke-authorizer",
        "--rest-api-id",
        api_id,
        "--authorizer-id",
        auth_id,
        "--headers",
        "{}",
        "--region",
        region,
    ]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        out = json.loads(res)
        policy = json.loads(out["policy"])
        effect = policy["policyDocument"]["Statement"][0]["Effect"]
        print(f"  Result: {effect}")
        if effect != "Deny":
            print("  FAIL: Expected Deny")
            sys.exit(1)
        else:
            print("  PASS")
    except subprocess.CalledProcessError as e:
        print(f"  AWS CLI Error: {e.output.decode()}")
        sys.exit(1)

    # 2. Test Valid Composite Cookie (Expect Allow)
    print("\n[2/2] Testing Valid Composite Cookie (North-South PK Lookup)...")
    ddb = boto3.resource("dynamodb", region_name=region)
    table = ddb.Table(table_name)

    tenant_id = "smoke-test-tenant"
    session_id = str(uuid.uuid4())

    # Composite PK format: APP#{app_id}#TENANT#{tenant_id}
    pk = f"APP#{app_id}#TENANT#{tenant_id}"
    sk = f"SESSION#{session_id}"

    table.put_item(
        Item={
            "pk": pk,
            "sk": sk,
            "tenant_id": tenant_id,
            "app_id": app_id,
            "access_token": "mock_token_smoke_test",
            "expires_at": int(time.time()) + 300,
        }
    )
    print(f"  Inserted mock session: PK={pk}, SK={sk}")

    # Valid Composite Cookie Header: session_id=tenant_id:session_id
    headers = {"Cookie": f"session_id={tenant_id}:{session_id}"}

    cmd = [
        "aws",
        "apigateway",
        "test-invoke-authorizer",
        "--rest-api-id",
        api_id,
        "--authorizer-id",
        auth_id,
        "--headers",
        json.dumps(headers),
        "--region",
        region,
    ]

    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        out = json.loads(res)
        policy = json.loads(out["policy"])
        effect = policy["policyDocument"]["Statement"][0]["Effect"]

        # Verify context propagation
        ctx = out.get("authorization", {})
        res_tenant = ctx.get("tenant_id")
        res_app = ctx.get("app_id")

        print(f"  Result: {effect}")
        print(f"  Context Tenant: {res_tenant}")
        print(f"  Context App: {res_app}")

        if effect != "Allow":
            print("  FAIL: Expected Allow")
            sys.exit(1)
        if res_tenant != tenant_id or res_app != app_id:
            print("  FAIL: Context propagation failed or mismatched")
            sys.exit(1)

        # Cleanup
        table.delete_item(Key={"pk": pk, "sk": sk})
        print("  PASS")
    except subprocess.CalledProcessError as e:
        print(f"  AWS CLI Error: {e.output.decode()}")
        sys.exit(1)

    print("\nBFF Smoke Test Successful.")


if __name__ == "__main__":
    main()

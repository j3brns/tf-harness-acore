#!/usr/bin/env python3
"""
Validate Bedrock inference profile docs (AWS Docs MCP) and Terraform support
(Terraform MCP) using MCP servers.
"""

import json
import os
import subprocess
import sys
import time


def send(proc, msg):
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()


def read_until_id(proc, target_id, timeout=20):
    start = time.time()
    while time.time() - start < timeout:
        line = proc.stdout.readline()
        if not line:
            continue
        line = line.strip()
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("id") == target_id:
            return msg
    return None


def start_server(cmd, env):
    return subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def init_server(proc):
    send(
        proc,
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "validate-inference-profiles", "version": "0.1"},
            },
        },
    )
    return read_until_id(proc, 1)


def tools_list(proc):
    send(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    return read_until_id(proc, 2)


def tools_call(proc, call_id, name, arguments):
    send(
        proc,
        {
            "jsonrpc": "2.0",
            "id": call_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments},
        },
    )
    return read_until_id(proc, call_id, timeout=30)


def extract_first_json_text(result):
    content = result.get("content", [])
    if not content:
        return None
    first = content[0]
    text = first.get("text") or first.get("content")
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def validate_aws_docs():
    cmd = [
        "uv",
        "tool",
        "run",
        "--from",
        "awslabs.aws-documentation-mcp-server@latest",
        "awslabs.aws-documentation-mcp-server",
    ]
    env = os.environ.copy()
    env.setdefault("FASTMCP_LOG_LEVEL", "ERROR")
    env.setdefault("AWS_DOCUMENTATION_PARTITION", "aws")
    env.setdefault("UV_CACHE_DIR", "/tmp/uv-cache")

    proc = start_server(cmd, env)
    if not init_server(proc):
        err = proc.stderr.read().strip()
        raise RuntimeError(f"AWS docs MCP init failed: {err}")
    send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})

    tools_resp = tools_list(proc)
    tools = [t.get("name") for t in tools_resp.get("result", {}).get("tools", [])]

    search_resp = tools_call(
        proc,
        3,
        "search_documentation",
        {"search_phrase": "Bedrock inference profiles create application inference profile"},
    )
    search_result = search_resp.get("result", {})
    search_json = extract_first_json_text(search_result) or {}
    top_hit = None
    if search_json.get("search_results"):
        top_hit = search_json["search_results"][0]

    proc.kill()
    return {"tools": tools, "top_hit": top_hit}


def validate_terraform_docs():
    cmd = [
        "uv",
        "tool",
        "run",
        "--from",
        "awslabs.terraform-mcp-server@latest",
        "awslabs.terraform-mcp-server",
    ]
    env = os.environ.copy()
    env.setdefault("FASTMCP_LOG_LEVEL", "ERROR")
    env.setdefault("UV_CACHE_DIR", "/tmp/uv-cache")

    proc = start_server(cmd, env)
    if not init_server(proc):
        err = proc.stderr.read().strip()
        raise RuntimeError(f"Terraform MCP init failed: {err}")
    send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})

    tools_resp = tools_list(proc)
    tools = [t.get("name") for t in tools_resp.get("result", {}).get("tools", [])]

    aws_provider = tools_call(proc, 3, "SearchAwsProviderDocs", {"query": "bedrock inference profile"})
    awscc_provider = tools_call(proc, 4, "SearchAwsccProviderDocs", {"query": "bedrock inference profile"})

    proc.kill()
    return {
        "tools": tools,
        "aws_provider": aws_provider.get("result", {}),
        "awscc_provider": awscc_provider.get("result", {}),
    }


def main():
    print("Validating AWS Docs MCP...")
    aws_docs = validate_aws_docs()
    print("AWS Docs MCP tools:", aws_docs["tools"])
    if aws_docs["top_hit"]:
        print("AWS Docs top hit:")
        print(json.dumps(aws_docs["top_hit"], indent=2))
    else:
        print("No AWS docs result found")

    print("\nValidating Terraform MCP...")
    tf_docs = validate_terraform_docs()
    print("Terraform MCP tools:", tf_docs["tools"])
    print("AWS provider search result snippet:")
    print(json.dumps(tf_docs["aws_provider"], indent=2)[:800])
    print("AWSCC provider search result snippet:")
    print(json.dumps(tf_docs["awscc_provider"], indent=2)[:800])

    return 0


if __name__ == "__main__":
    sys.exit(main())

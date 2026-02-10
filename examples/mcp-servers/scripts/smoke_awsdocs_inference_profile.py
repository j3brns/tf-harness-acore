#!/usr/bin/env python3
"""
Smoke test for the AWS Documentation MCP server.

Searches for Bedrock inference profile docs and prints the top result.
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


def main():
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

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )

    send(
        proc,
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "smoke-test", "version": "0.1"},
            },
        },
    )
    if not read_until_id(proc, 1):
        err = proc.stderr.read().strip()
        print("ERROR: no initialize response")
        if err:
            print("STDERR:", err[:400])
        proc.kill()
        return 1

    send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})

    send(
        proc,
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "search_documentation",
                "arguments": {
                    "search_phrase": "Bedrock inference profiles create application inference profile"
                },
            },
        },
    )
    resp = read_until_id(proc, 2, timeout=30)
    if not resp:
        err = proc.stderr.read().strip()
        print("ERROR: no tools/call response")
        if err:
            print("STDERR:", err[:400])
        proc.kill()
        return 1

    result = resp.get("result", {})
    content = result.get("content", [])
    if not content:
        print("ERROR: empty result")
        proc.kill()
        return 1

    first = content[0]
    text = first.get("text") or first.get("content") or str(first)
    print(text[:400])

    proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())

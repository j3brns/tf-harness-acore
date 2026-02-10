#!/usr/bin/env python3
"""
Smoke test for the Terraform MCP server.

Starts the server, lists tools, and prints the tool names.
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
        "awslabs.terraform-mcp-server@latest",
        "awslabs.terraform-mcp-server",
    ]

    env = os.environ.copy()
    env.setdefault("FASTMCP_LOG_LEVEL", "ERROR")
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
            "method": "tools/list",
            "params": {},
        },
    )
    resp = read_until_id(proc, 2, timeout=30)
    if not resp:
        err = proc.stderr.read().strip()
        print("ERROR: no tools/list response")
        if err:
            print("STDERR:", err[:400])
        proc.kill()
        return 1

    tools = [t.get("name") for t in resp.get("result", {}).get("tools", [])]
    print("TOOLS", tools)

    proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
